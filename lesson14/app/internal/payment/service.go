package payment

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
)

// ConsumerName is this service's queue on the local bus (on AWS, QUEUE_URL already names it).
const ConsumerName = "payment"

const declinedReason = "card declined (demo rule: totals ending in 99)"

// Decide is the lab's deterministic card: a total whose cents end in 99 is declined, anything else is paid.
func Decide(totalCents int64) (status, reason string) {
	if totalCents%100 == 99 {
		return Failed, declinedReason
	}
	return Succeeded, ""
}

type Service struct {
	store Store
	pub   events.Publisher
	log   *slog.Logger
}

func NewService(s Store, pub events.Publisher, log *slog.Logger) *Service {
	return &Service{store: s, pub: pub, log: log}
}

// ByOrder returns the caller's payment for an order; another customer's is ErrNotFound.
func (s *Service) ByOrder(ctx context.Context, orderID, sub string) (Payment, error) {
	return s.store.ByOrder(ctx, orderID, sub)
}

// HandleEvent charges an OrderCreated and publishes the outcome. A redelivered event is skipped once its
// payment row exists. The row is written after the publish, so a failed publish (or a crash before it)
// leaves no row and the redelivery publishes again instead of being lost; a crash between publish and
// insert can repeat the outcome event, which Order (status check) and Notification tolerate.
func (s *Service) HandleEvent(ctx context.Context, e events.Event) error {
	if e.EventType != events.OrderCreated {
		s.log.Debug("ignoring event", "event_id", e.EventID, "event_type", e.EventType)
		return nil
	}

	first, err := s.store.MarkProcessed(ctx, e.EventID)
	if err != nil {
		return err
	}
	if !first {
		_, err := s.store.ByOrder(ctx, e.OrderID, e.CustomerSub)
		if err == nil {
			s.log.Info("duplicate event ignored", "event_id", e.EventID, "order_id", e.OrderID)
			return nil
		}
		if !errors.Is(err, ErrNotFound) {
			return err
		}
		// Marked but no row: the earlier attempt failed before finishing, so finish it now.
	}

	status, reason := Decide(e.TotalCents)
	p := Payment{
		ID:          newID("pay-"),
		OrderID:     e.OrderID,
		CustomerSub: e.CustomerSub,
		AmountCents: e.TotalCents,
		Status:      status,
		Reason:      reason,
		CreatedAt:   time.Now().UTC(),
	}

	outcome := events.PaymentSucceeded
	if status == Failed {
		outcome = events.PaymentFailed
	}
	out := events.New(outcome, e.OrderID, e.CustomerSub, e.Email, e.TotalCents)
	out.Reason = reason
	if err := s.pub.Publish(ctx, out); err != nil {
		return fmt.Errorf("publish %s for %s: %w", outcome, e.OrderID, err)
	}

	if err := s.store.Create(ctx, p); err != nil {
		if errors.Is(err, ErrDuplicateOrder) {
			s.log.Warn("payment for order already recorded", "order_id", e.OrderID, "event_id", e.EventID)
			return nil
		}
		return fmt.Errorf("create payment for %s: %w", e.OrderID, err)
	}
	s.log.Info("payment recorded", "payment_id", p.ID, "order_id", p.OrderID, "status", p.Status, "amount_cents", p.AmountCents)
	return nil
}

// newID returns prefix + 8 random hex characters.
func newID(prefix string) string {
	b := make([]byte, 4)
	_, _ = rand.Read(b) // crypto/rand.Read never fails on supported platforms
	return prefix + hex.EncodeToString(b)
}
