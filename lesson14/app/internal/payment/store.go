// Package payment is the Payment Service: it charges each OrderCreated with a deterministic demo rule
// and publishes PaymentSucceeded or PaymentFailed.
package payment

import (
	"context"
	"errors"
	"time"
)

const (
	Succeeded = "SUCCEEDED"
	Failed    = "FAILED"
)

// Payment is what GET /api/payments/{orderId} returns; one per order.
type Payment struct {
	ID          string    `json:"id"`
	OrderID     string    `json:"order_id"`
	CustomerSub string    `json:"customer_sub"`
	AmountCents int64     `json:"amount_cents"`
	Status      string    `json:"status"`
	Reason      string    `json:"reason"`
	CreatedAt   time.Time `json:"created_at"`
}

var (
	// ErrNotFound: no payment for the order, or it belongs to another customer.
	ErrNotFound = errors.New("payment not found")
	// ErrDuplicateOrder: Create found a payment for the order already (order_id is unique).
	ErrDuplicateOrder = errors.New("payment for order already exists")
)

// Store persists payments in the payments schema. MarkProcessed records an event id and reports whether
// this is its first delivery.
type Store interface {
	Create(ctx context.Context, p Payment) error
	ByOrder(ctx context.Context, orderID, sub string) (Payment, error)
	MarkProcessed(ctx context.Context, eventID string) (bool, error)
}
