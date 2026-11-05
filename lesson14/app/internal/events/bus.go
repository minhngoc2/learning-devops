package events

import (
	"context"
	"errors"
	"fmt"
	"log/slog"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/sqs"

	"github.com/minhngoc2/learning-devops/lesson14/internal/config"
)

// Publisher sends one event to every subscribed consumer.
type Publisher interface {
	Publish(ctx context.Context, e Event) error
}

// Handler processes one event. Returning nil acknowledges (deletes) it; an error leaves it for redelivery.
type Handler func(ctx context.Context, e Event) error

// Consumer delivers events to h until ctx is cancelled, then returns nil. Delivery is at least once,
// so handlers must be idempotent (dedupe on EventID or a natural key).
type Consumer interface {
	Run(ctx context.Context, h Handler) error
}

// incomplete reports (and logs at warn) an event without event_id or event_type. Consumers ack such a
// message without calling the handler: redelivering it cannot help, and handlers dedupe on EventID.
func incomplete(log *slog.Logger, e Event) bool {
	if e.EventID != "" && e.EventType != "" {
		return false
	}
	log.Warn("event without event_id or event_type; acking it unhandled", "event_id", e.EventID, "event_type", e.EventType, "order_id", e.OrderID)
	return true
}

// PublisherFromEnv picks the bus from EVENT_BUS: "sns" (TOPIC_ARN, AWS_REGION) or "local" (EVENT_BUS_URL).
func PublisherFromEnv(ctx context.Context) (Publisher, error) {
	switch bus := config.Get("EVENT_BUS", ""); bus {
	case "sns":
		topic := config.Get("TOPIC_ARN", "")
		if topic == "" {
			return nil, errors.New("events: EVENT_BUS=sns needs TOPIC_ARN")
		}
		cfg, err := awsconfig.LoadDefaultConfig(ctx)
		if err != nil {
			return nil, fmt.Errorf("events: aws config: %w", err)
		}
		return NewSNSPublisher(sns.NewFromConfig(cfg), topic), nil
	case "local":
		url := config.Get("EVENT_BUS_URL", "")
		if url == "" {
			return nil, errors.New("events: EVENT_BUS=local needs EVENT_BUS_URL")
		}
		return NewLocalPublisher(url), nil
	default:
		return nil, fmt.Errorf("events: EVENT_BUS must be sns or local, got %q", bus)
	}
}

// ConsumerFromEnv picks the bus from EVENT_BUS: "sns" reads QUEUE_URL, "local" reads EVENT_BUS_URL and
// polls as consumer. The SQS consumer logs through slog.Default(), so call slog.SetDefault first.
func ConsumerFromEnv(ctx context.Context, consumer string) (Consumer, error) {
	switch bus := config.Get("EVENT_BUS", ""); bus {
	case "sns":
		queue := config.Get("QUEUE_URL", "")
		if queue == "" {
			return nil, errors.New("events: EVENT_BUS=sns needs QUEUE_URL")
		}
		cfg, err := awsconfig.LoadDefaultConfig(ctx)
		if err != nil {
			return nil, fmt.Errorf("events: aws config: %w", err)
		}
		return NewSQSConsumer(sqs.NewFromConfig(cfg), queue, slog.Default()), nil
	case "local":
		url := config.Get("EVENT_BUS_URL", "")
		if url == "" {
			return nil, errors.New("events: EVENT_BUS=local needs EVENT_BUS_URL")
		}
		return NewLocalConsumer(url, consumer), nil
	default:
		return nil, fmt.Errorf("events: EVENT_BUS must be sns or local, got %q", bus)
	}
}
