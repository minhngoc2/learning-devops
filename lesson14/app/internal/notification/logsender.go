package notification

import (
	"context"
	"log/slog"
)

type logSender struct{ log *slog.Logger }

// NewLogSender writes each email to the log instead of sending it (NOTIFY_MODE=log: compose, or AWS
// without a verified SES identity).
func NewLogSender(log *slog.Logger) Sender { return logSender{log: log} }

func (s logSender) Send(ctx context.Context, to, subject, body string) error {
	s.log.InfoContext(ctx, "email (log mode, not sent)", "to", to, "subject", subject, "body", body)
	return nil
}
