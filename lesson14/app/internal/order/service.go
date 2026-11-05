package order

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
	"github.com/minhngoc2/learning-devops/lesson14/internal/ids"
)

// ErrEmptyCart: checkout of a cart with no lines (422).
var ErrEmptyCart = errors.New("cart is empty")

// ErrUnknownProduct: a cart line names a product the catalog no longer has (422).
type ErrUnknownProduct struct{ ID string }

func (e ErrUnknownProduct) Error() string { return "unknown product " + e.ID }

const currency = "VND"

type Service struct {
	store    Store
	cart     CartClient
	products ProductClient
	pub      events.Publisher
	log      *slog.Logger
}

func NewService(s Store, c CartClient, p ProductClient, pub events.Publisher, log *slog.Logger) *Service {
	return &Service{store: s, cart: c, products: p, pub: pub, log: log}
}

// Checkout turns the caller's cart into a PENDING_PAYMENT order priced from the catalog, publishes
// OrderCreated (Payment and Notification take it from there) and then clears the cart. Clearing is
// best-effort: the order already exists, so a failure is only logged.
func (s *Service) Checkout(ctx context.Context, id httpx.Identity) (Order, error) {
	lines, err := s.cart.Get(ctx, id.Sub)
	if err != nil {
		return Order{}, fmt.Errorf("read cart: %w", err)
	}
	if len(lines) == 0 {
		return Order{}, ErrEmptyCart
	}

	productIDs := make([]string, len(lines))
	for i, l := range lines {
		productIDs[i] = l.ProductID
	}
	products, err := s.products.ByIDs(ctx, productIDs)
	if err != nil {
		return Order{}, fmt.Errorf("read products: %w", err)
	}

	now := time.Now().UTC()
	o := Order{ID: ids.New("ord-"), CustomerSub: id.Sub, Status: PendingPayment, Currency: currency, Items: make([]Item, 0, len(lines)), CreatedAt: now, UpdatedAt: now}
	for _, l := range lines {
		p, ok := products[l.ProductID]
		if !ok {
			return Order{}, ErrUnknownProduct{ID: l.ProductID}
		}
		o.Items = append(o.Items, Item{ProductID: p.ID, Name: p.Name, UnitPriceCents: p.PriceCents, Quantity: l.Quantity})
		o.TotalCents += p.PriceCents * int64(l.Quantity)
	}

	if err := s.store.Create(ctx, o); err != nil {
		return Order{}, fmt.Errorf("create order: %w", err)
	}
	// Email may be "" (ID token without the claim); Notification then skips the email.
	if err := s.pub.Publish(ctx, events.New(events.OrderCreated, o.ID, o.CustomerSub, id.Email, o.TotalCents)); err != nil {
		return Order{}, fmt.Errorf("publish OrderCreated for %s: %w", o.ID, err)
	}
	if err := s.cart.Clear(ctx, id.Sub); err != nil {
		s.log.Warn("order created but clearing the cart failed", "order_id", o.ID, "customer_sub", id.Sub, "err", err)
	}
	s.log.Info("order created", "order_id", o.ID, "customer_sub", o.CustomerSub, "total_cents", o.TotalCents)
	return o, nil
}

// Get returns the caller's order; another customer's order is ErrNotFound.
func (s *Service) Get(ctx context.Context, id, sub string) (Order, error) {
	return s.store.Get(ctx, id, sub)
}

func (s *Service) List(ctx context.Context, sub string) ([]Order, error) {
	return s.store.List(ctx, sub)
}

// HandleEvent finishes an order from a payment outcome: PaymentSucceeded → PAID, PaymentFailed →
// PAYMENT_FAILED. A redelivered event (EventID already in processed_events) changes nothing, unless the
// earlier attempt recorded the event but failed before the update, in which case the update runs now.
func (s *Service) HandleEvent(ctx context.Context, e events.Event) error {
	var target Status
	switch e.EventType {
	case events.PaymentSucceeded:
		target = Paid
	case events.PaymentFailed:
		target = PaymentFailed
	default:
		s.log.Debug("ignoring event", "event_id", e.EventID, "event_type", e.EventType)
		return nil
	}

	first, err := s.store.MarkProcessed(ctx, e.EventID)
	if err != nil {
		return err
	}
	if !first {
		o, err := s.store.Get(ctx, e.OrderID, e.CustomerSub)
		if errors.Is(err, ErrNotFound) {
			return nil
		}
		if err != nil {
			return err
		}
		if o.Status != PendingPayment {
			s.log.Info("duplicate event ignored", "event_id", e.EventID, "event_type", e.EventType, "order_id", e.OrderID)
			return nil
		}
	}

	if err := s.store.SetStatus(ctx, e.OrderID, target); err != nil {
		if errors.Is(err, ErrNotFound) {
			s.log.Warn("payment event for unknown order; dropping it", "event_id", e.EventID, "order_id", e.OrderID)
			return nil
		}
		return fmt.Errorf("set order %s %s: %w", e.OrderID, target, err)
	}
	s.log.Info("order status updated", "order_id", e.OrderID, "status", target, "event_id", e.EventID)
	return nil
}
