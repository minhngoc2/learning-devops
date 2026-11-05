package events

import (
	"context"
	"encoding/json"
	"log/slog"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

// QueueAPI is the part of *sqs.Client the consumer uses; tests pass a fake.
type QueueAPI interface {
	ReceiveMessage(ctx context.Context, in *sqs.ReceiveMessageInput, optFns ...func(*sqs.Options)) (*sqs.ReceiveMessageOutput, error)
	DeleteMessage(ctx context.Context, in *sqs.DeleteMessageInput, optFns ...func(*sqs.Options)) (*sqs.DeleteMessageOutput, error)
}

type sqsConsumer struct {
	api      QueueAPI
	queueURL string
	log      *slog.Logger
}

// NewSQSConsumer long-polls the queue (20 s, up to 10 messages). The subscription uses raw delivery, so
// each body is the event JSON. A message is deleted when the handler returns nil; otherwise it is left
// to reappear after the visibility timeout, and SQS moves it to the DLQ after 5 receives.
func NewSQSConsumer(client *sqs.Client, queueURL string, log *slog.Logger) Consumer {
	return &sqsConsumer{api: client, queueURL: queueURL, log: log}
}

func (c *sqsConsumer) Run(ctx context.Context, h Handler) error {
	for ctx.Err() == nil {
		out, err := c.api.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
			QueueUrl:            aws.String(c.queueURL),
			MaxNumberOfMessages: 10,
			WaitTimeSeconds:     20,
		})
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			c.log.Error("sqs receive", "queue_url", c.queueURL, "err", err)
			select {
			case <-ctx.Done():
			case <-time.After(5 * time.Second):
			}
			continue
		}
		for _, m := range out.Messages {
			var e Event
			if err := json.Unmarshal([]byte(aws.ToString(m.Body)), &e); err != nil {
				c.log.Error("sqs message is not an event; leaving it for the DLQ", "message_id", aws.ToString(m.MessageId), "err", err)
				continue
			}
			if err := h(ctx, e); err != nil {
				c.log.Error("handle event; leaving it for redelivery", "event_id", e.EventID, "event_type", e.EventType, "err", err)
				continue
			}
			// Delete even if ctx was just cancelled: the work is done.
			if _, err := c.api.DeleteMessage(context.WithoutCancel(ctx), &sqs.DeleteMessageInput{
				QueueUrl:      aws.String(c.queueURL),
				ReceiptHandle: m.ReceiptHandle,
			}); err != nil {
				c.log.Error("sqs delete", "event_id", e.EventID, "err", err)
			}
		}
	}
	return nil
}
