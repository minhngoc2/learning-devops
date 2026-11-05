// Package notification is the Notification Service: it emails the customer about each order event.
package notification

import "context"

// Sender delivers one plain-text email. An error means "not sent"; the event is then retried.
type Sender interface {
	Send(ctx context.Context, to, subject, body string) error
}
