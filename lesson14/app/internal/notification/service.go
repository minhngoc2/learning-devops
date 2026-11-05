package notification

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
)

// ConsumerName is this service's queue on the local bus (on AWS, QUEUE_URL already names it).
const ConsumerName = "notification"

// Compose returns the email for an event. Unknown types get an empty subject.
func Compose(e events.Event) (subject, body string) {
	total := fmt.Sprintf("%d %s", e.TotalCents, e.Currency)
	switch e.EventType {
	case events.OrderCreated:
		return "Order " + e.OrderID + " received",
			fmt.Sprintf("We received order %s (total %s) and are processing the payment.", e.OrderID, total)
	case events.PaymentSucceeded:
		return "Order " + e.OrderID + " paid",
			fmt.Sprintf("Payment for order %s (total %s) succeeded. Thank you!", e.OrderID, total)
	case events.PaymentFailed:
		return "Payment for order " + e.OrderID + " failed: " + e.Reason,
			fmt.Sprintf("Payment for order %s (total %s) failed: %s.", e.OrderID, total, e.Reason)
	}
	return "", ""
}

type Service struct {
	sender Sender
	log    *slog.Logger
}

func NewService(sender Sender, log *slog.Logger) *Service {
	return &Service{sender: sender, log: log}
}

// HandleEvent emails the customer. No email address (ID token without the claim) → logged and acked.
// A send error is returned so the queue redelivers (and, after 5 tries, dead-letters) the event. There is
// no dedupe: a rare duplicate email is accepted.
func (s *Service) HandleEvent(ctx context.Context, e events.Event) error {
	subject, body := Compose(e)
	if subject == "" {
		s.log.Debug("ignoring event", "event_id", e.EventID, "event_type", e.EventType)
		return nil
	}
	if e.Email == "" {
		s.log.Info("no email address on event; skipping notification", "event_id", e.EventID, "event_type", e.EventType, "order_id", e.OrderID)
		return nil
	}
	if err := s.sender.Send(ctx, e.Email, subject, body); err != nil {
		return fmt.Errorf("notify %s for %s: %w", e.EventType, e.OrderID, err)
	}
	s.log.Info("notification sent", "event_id", e.EventID, "event_type", e.EventType, "order_id", e.OrderID)
	return nil
}
