// Package events carries order events between services: SNS → SQS on AWS, an in-process bus in tests,
// and the cmd/localbus HTTP bus in compose.
package events

import (
	"time"

	"github.com/google/uuid"
)

const (
	OrderCreated     = "OrderCreated"
	PaymentSucceeded = "PaymentSucceeded"
	PaymentFailed    = "PaymentFailed"
)

// Event is the one message shape on the bus. Email may be empty (ID token without an email claim);
// Reason is set only on PaymentFailed.
type Event struct {
	EventID     string `json:"event_id"`
	EventType   string `json:"event_type"`
	OccurredAt  string `json:"occurred_at"`
	OrderID     string `json:"order_id"`
	CustomerSub string `json:"customer_sub"`
	Currency    string `json:"currency"`
	Email       string `json:"email"`
	Reason      string `json:"reason"`
	TotalCents  int64  `json:"total_cents"`
}

// New returns an event with a fresh UUID v4, the current UTC time in RFC 3339 and currency VND.
func New(eventType, orderID, sub, email string, total int64) Event {
	return Event{
		EventID:     uuid.NewString(),
		EventType:   eventType,
		OccurredAt:  time.Now().UTC().Format(time.RFC3339),
		OrderID:     orderID,
		CustomerSub: sub,
		Currency:    "VND",
		Email:       email,
		TotalCents:  total,
	}
}
