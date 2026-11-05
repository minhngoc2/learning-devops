package notification

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sesv2"

	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
)

type sent struct{ to, subject, body string }

type fakeSender struct {
	sent []sent
	err  error
}

func (f *fakeSender) Send(_ context.Context, to, subject, body string) error {
	if f.err != nil {
		return f.err
	}
	f.sent = append(f.sent, sent{to, subject, body})
	return nil
}

func discard() *slog.Logger { return slog.New(slog.NewJSONHandler(io.Discard, nil)) }

func TestCompose_ThreeTypes(t *testing.T) {
	failed := events.New(events.PaymentFailed, "ord-1", "sub-1", "a@example.com", 1999)
	failed.Reason = "card declined (demo rule: totals ending in 99)"
	cases := []struct {
		e           events.Event
		wantSubject string
	}{
		{events.New(events.OrderCreated, "ord-1", "sub-1", "a@example.com", 2000), "Order ord-1 received"},
		{events.New(events.PaymentSucceeded, "ord-1", "sub-1", "a@example.com", 2000), "Order ord-1 paid"},
		{failed, "Payment for order ord-1 failed: card declined (demo rule: totals ending in 99)"},
	}
	for _, c := range cases {
		subject, body := Compose(c.e)
		if subject != c.wantSubject {
			t.Errorf("%s: subject = %q, want %q", c.e.EventType, subject, c.wantSubject)
		}
		if !strings.Contains(body, "ord-1") {
			t.Errorf("%s: body %q does not mention the order", c.e.EventType, body)
		}
	}
}

func TestHandle_SendsToCustomerEmail(t *testing.T) {
	sender := &fakeSender{}
	svc := NewService(sender, discard())

	if err := svc.HandleEvent(context.Background(), events.New(events.PaymentSucceeded, "ord-7", "sub-1", "a@example.com", 2000)); err != nil {
		t.Fatalf("HandleEvent: %v", err)
	}
	if len(sender.sent) != 1 || sender.sent[0].to != "a@example.com" || sender.sent[0].subject != "Order ord-7 paid" {
		t.Errorf("sent = %+v", sender.sent)
	}
}

func TestHandle_EmptyEmailSkipsSend(t *testing.T) {
	sender := &fakeSender{}
	svc := NewService(sender, discard())

	if err := svc.HandleEvent(context.Background(), events.New(events.OrderCreated, "ord-7", "sub-1", "", 2000)); err != nil {
		t.Fatalf("HandleEvent: %v, want nil (ack)", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("sent = %+v, want nothing", sender.sent)
	}
}

func TestHandle_SenderErrorReturnsErrorForRetry(t *testing.T) {
	boom := errors.New("ses throttled")
	svc := NewService(&fakeSender{err: boom}, discard())

	err := svc.HandleEvent(context.Background(), events.New(events.OrderCreated, "ord-7", "sub-1", "a@example.com", 2000))
	if !errors.Is(err, boom) {
		t.Errorf("err = %v, want it to wrap %v", err, boom)
	}
}

type fakeSES struct{ in *sesv2.SendEmailInput }

func (f *fakeSES) SendEmail(_ context.Context, in *sesv2.SendEmailInput, _ ...func(*sesv2.Options)) (*sesv2.SendEmailOutput, error) {
	f.in = in
	return &sesv2.SendEmailOutput{MessageId: aws.String("m-1")}, nil
}

func TestSESSender_SimpleContentFromConfiguredAddress(t *testing.T) {
	api := &fakeSES{}
	s := &sesSender{api: api, from: "shop@example.com"}

	if err := s.Send(context.Background(), "a@example.com", "Order ord-1 paid", "Thanks"); err != nil {
		t.Fatalf("Send: %v", err)
	}
	in := api.in
	if aws.ToString(in.FromEmailAddress) != "shop@example.com" || len(in.Destination.ToAddresses) != 1 || in.Destination.ToAddresses[0] != "a@example.com" {
		t.Errorf("input = %+v", in)
	}
	simple := in.Content.Simple
	if simple == nil || aws.ToString(simple.Subject.Data) != "Order ord-1 paid" || aws.ToString(simple.Body.Text.Data) != "Thanks" {
		t.Errorf("content = %+v", in.Content)
	}
}
