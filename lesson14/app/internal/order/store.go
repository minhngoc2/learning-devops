// Package order is the Order Service: checkout turns the caller's Cart into a PENDING_PAYMENT Order,
// publishes OrderCreated, and payment events finish the Order as PAID or PAYMENT_FAILED.
package order

import (
	"context"
	"errors"
	"time"
)

type Status string

const (
	PendingPayment Status = "PENDING_PAYMENT"
	Paid           Status = "PAID"
	PaymentFailed  Status = "PAYMENT_FAILED"
)

// Item is one order line with the product's name and price copied at checkout.
type Item struct {
	ProductID      string `json:"product_id"`
	Name           string `json:"name"`
	UnitPriceCents int64  `json:"unit_price_cents"`
	Quantity       int    `json:"quantity"`
}

// Order is what the API returns. Items is never nil.
type Order struct {
	ID          string    `json:"id"`
	CustomerSub string    `json:"customer_sub"`
	Status      Status    `json:"status"`
	TotalCents  int64     `json:"total_cents"`
	Currency    string    `json:"currency"`
	Items       []Item    `json:"items"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// ErrNotFound is returned by Get and SetStatus for a missing order, and by Get for another customer's.
var ErrNotFound = errors.New("order not found")

// Store persists orders in the orders schema. List returns the customer's orders newest first (never nil).
// MarkProcessed records an event id and reports whether this is its first delivery.
type Store interface {
	Create(ctx context.Context, o Order) error
	Get(ctx context.Context, id, sub string) (Order, error)
	List(ctx context.Context, sub string) ([]Order, error)
	SetStatus(ctx context.Context, id string, s Status) error
	MarkProcessed(ctx context.Context, eventID string) (first bool, err error)
}
