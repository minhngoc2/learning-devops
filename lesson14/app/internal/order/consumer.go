package order

import (
	"context"

	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
)

// ConsumerName is this service's queue on the local bus (on AWS, QUEUE_URL already names it).
const ConsumerName = "order"

// Consume feeds payment events from c to s.HandleEvent until ctx is cancelled.
func Consume(ctx context.Context, c events.Consumer, s *Service) error {
	return c.Run(ctx, s.HandleEvent)
}
