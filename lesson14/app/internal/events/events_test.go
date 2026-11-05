package events

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/google/uuid"
)

// received runs c until it has delivered want events or wait elapses, and returns what it got.
func received(t *testing.T, c Consumer, want int, wait time.Duration) []Event {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	var got []Event
	err := c.Run(ctx, func(_ context.Context, e Event) error {
		got = append(got, e)
		if len(got) == want {
			cancel()
		}
		return nil
	})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	return got
}

func TestMemoryBus_FanOutByType(t *testing.T) {
	bus := NewMemoryBus()
	payment := bus.Consumer("payment", []string{OrderCreated})
	order := bus.Consumer("order", []string{PaymentSucceeded, PaymentFailed})
	notification := bus.Consumer("notification", []string{OrderCreated, PaymentSucceeded, PaymentFailed})

	e := New(OrderCreated, "ord-1", "sub-1", "a@example.com", 150000)
	if err := bus.Publish(context.Background(), e); err != nil {
		t.Fatalf("Publish: %v", err)
	}

	for name, c := range map[string]Consumer{"payment": payment, "notification": notification} {
		got := received(t, c, 1, time.Second)
		if len(got) != 1 || got[0] != e {
			t.Errorf("%s received %+v, want [%+v]", name, got, e)
		}
	}
	if got := received(t, order, 1, 50*time.Millisecond); len(got) != 0 {
		t.Errorf("order received %+v, want nothing", got)
	}
}

func TestNew_FillsIDAndTimestamp(t *testing.T) {
	before := time.Now().Add(-time.Second)
	e := New(PaymentFailed, "ord-9", "sub-9", "", 1099)

	if _, err := uuid.Parse(e.EventID); err != nil {
		t.Errorf("EventID %q is not a UUID: %v", e.EventID, err)
	}
	ts, err := time.Parse(time.RFC3339, e.OccurredAt)
	if err != nil || ts.Before(before.Truncate(time.Second)) {
		t.Errorf("OccurredAt = %q (err %v), want RFC3339 now", e.OccurredAt, err)
	}
	if e.EventType != PaymentFailed || e.OrderID != "ord-9" || e.CustomerSub != "sub-9" || e.TotalCents != 1099 || e.Currency != "VND" {
		t.Errorf("event = %+v", e)
	}
	if New(OrderCreated, "o", "s", "", 1).EventID == e.EventID {
		t.Error("two events share an EventID")
	}
}

type fakePublishAPI struct{ input *sns.PublishInput }

func (f *fakePublishAPI) Publish(_ context.Context, in *sns.PublishInput, _ ...func(*sns.Options)) (*sns.PublishOutput, error) {
	f.input = in
	return &sns.PublishOutput{MessageId: aws.String("m-1")}, nil
}

func TestSNSPublisher_SetsEventTypeAttribute(t *testing.T) {
	fake := &fakePublishAPI{}
	p := &snsPublisher{api: fake, topicARN: "arn:aws:sns:ap-southeast-1:123456789012:lesson14-dev-order-events"}
	e := New(OrderCreated, "ord-1", "sub-1", "", 250000)

	if err := p.Publish(context.Background(), e); err != nil {
		t.Fatalf("Publish: %v", err)
	}
	in := fake.input
	if in == nil || aws.ToString(in.TopicArn) != p.topicARN {
		t.Fatalf("input = %+v, want topic %s", in, p.topicARN)
	}
	attr, ok := in.MessageAttributes["event_type"]
	if !ok || aws.ToString(attr.DataType) != "String" || aws.ToString(attr.StringValue) != OrderCreated {
		t.Errorf("event_type attribute = %+v", attr)
	}
	var body map[string]any
	if err := json.Unmarshal([]byte(aws.ToString(in.Message)), &body); err != nil {
		t.Fatalf("message is not JSON: %v", err)
	}
	if body["event_type"] != OrderCreated || body["order_id"] != "ord-1" || body["email"] != "" || body["total_cents"] != float64(250000) {
		t.Errorf("message body = %v", body)
	}
}
