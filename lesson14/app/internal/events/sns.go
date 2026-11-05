package events

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/aws/aws-sdk-go-v2/service/sns/types"
)

// PublishAPI is the part of *sns.Client the publisher uses; tests pass a fake.
type PublishAPI interface {
	Publish(ctx context.Context, in *sns.PublishInput, optFns ...func(*sns.Options)) (*sns.PublishOutput, error)
}

type snsPublisher struct {
	api      PublishAPI
	topicARN string
}

// NewSNSPublisher publishes the event JSON to the topic with message attribute event_type (String),
// which the queue subscriptions' filter policies match on.
func NewSNSPublisher(client *sns.Client, topicARN string) Publisher {
	return &snsPublisher{api: client, topicARN: topicARN}
}

func (p *snsPublisher) Publish(ctx context.Context, e Event) error {
	body, err := json.Marshal(e)
	if err != nil {
		return err
	}
	_, err = p.api.Publish(ctx, &sns.PublishInput{
		TopicArn: aws.String(p.topicARN),
		Message:  aws.String(string(body)),
		MessageAttributes: map[string]types.MessageAttributeValue{
			"event_type": {DataType: aws.String("String"), StringValue: aws.String(e.EventType)},
		},
	})
	if err != nil {
		return fmt.Errorf("sns publish %s %s: %w", e.EventType, e.EventID, err)
	}
	return nil
}
