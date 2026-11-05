package events

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
)

// fakeQueue hands out its messages on the first ReceiveMessage, then blocks until ctx is cancelled like
// an empty long poll. It records the receipt handles it was asked to delete.
type fakeQueue struct {
	mu       sync.Mutex
	messages []types.Message
	deleted  []string
}

func (f *fakeQueue) ReceiveMessage(ctx context.Context, _ *sqs.ReceiveMessageInput, _ ...func(*sqs.Options)) (*sqs.ReceiveMessageOutput, error) {
	f.mu.Lock()
	msgs := f.messages
	f.messages = nil
	f.mu.Unlock()
	if len(msgs) > 0 {
		return &sqs.ReceiveMessageOutput{Messages: msgs}, nil
	}
	<-ctx.Done()
	return nil, ctx.Err()
}

func (f *fakeQueue) DeleteMessage(_ context.Context, in *sqs.DeleteMessageInput, _ ...func(*sqs.Options)) (*sqs.DeleteMessageOutput, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.deleted = append(f.deleted, aws.ToString(in.ReceiptHandle))
	return &sqs.DeleteMessageOutput{}, nil
}

func message(t *testing.T, receipt string, body any) types.Message {
	t.Helper()
	b, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	return types.Message{MessageId: aws.String("m-" + receipt), ReceiptHandle: aws.String(receipt), Body: aws.String(string(b))}
}

// runSQS runs the consumer until the handler has seen want events (or 2 s pass), then cancels it and
// returns Run's error.
func runSQS(t *testing.T, q *fakeQueue, log *slog.Logger, want int, h Handler) error {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var mu sync.Mutex
	seen := 0
	c := &sqsConsumer{api: q, queueURL: "https://sqs.example/q", log: log}
	done := make(chan error, 1)
	go func() {
		done <- c.Run(ctx, func(ctx context.Context, e Event) error {
			err := h(ctx, e)
			mu.Lock()
			seen++
			if seen == want {
				// Let Run finish the batch (the delete) before the cancel.
				defer func() { go func() { time.Sleep(50 * time.Millisecond); cancel() }() }()
			}
			mu.Unlock()
			return err
		})
	}()
	select {
	case err := <-done:
		return err
	case <-time.After(3 * time.Second):
		t.Fatal("Run did not return after ctx cancel")
		return nil
	}
}

func TestSQSConsumer_DeletesOnlyOnNil(t *testing.T) {
	first, second := New(OrderCreated, "ord-1", "sub-1", "", 100), New(OrderCreated, "ord-2", "sub-1", "", 200)
	q := &fakeQueue{messages: []types.Message{message(t, "r-1", first), message(t, "r-2", second)}}
	var handled []string
	err := runSQS(t, q, slog.New(slog.NewJSONHandler(io.Discard, nil)), 2, func(_ context.Context, e Event) error {
		handled = append(handled, e.OrderID)
		if e.OrderID == "ord-1" {
			return errors.New("transient")
		}
		return nil
	})
	if err != nil {
		t.Errorf("Run = %v, want nil after ctx cancel", err)
	}
	if strings.Join(handled, ",") != "ord-1,ord-2" {
		t.Errorf("handled = %v", handled)
	}
	if strings.Join(q.deleted, ",") != "r-2" {
		t.Errorf("deleted = %v, want exactly [r-2]", q.deleted)
	}
}

func TestSQSConsumer_AcksEventWithoutIDOrTypeWithoutHandling(t *testing.T) {
	ok := New(OrderCreated, "ord-1", "sub-1", "", 100)
	noID, noType := ok, ok
	noID.EventID = ""
	noType.EventType = ""
	q := &fakeQueue{messages: []types.Message{message(t, "r-noid", noID), message(t, "r-notype", noType), message(t, "r-ok", ok)}}
	var logs bytes.Buffer
	var handled []Event
	err := runSQS(t, q, slog.New(slog.NewJSONHandler(&logs, nil)), 1, func(_ context.Context, e Event) error {
		handled = append(handled, e)
		return nil
	})
	if err != nil {
		t.Errorf("Run = %v", err)
	}
	if len(handled) != 1 || handled[0].EventID != ok.EventID {
		t.Errorf("handled = %+v, want only the complete event", handled)
	}
	if strings.Join(q.deleted, ",") != "r-noid,r-notype,r-ok" {
		t.Errorf("deleted = %v, want all three", q.deleted)
	}
	if n := strings.Count(logs.String(), `"level":"WARN"`); n != 2 {
		t.Errorf("warn lines = %d, want 2; logs:\n%s", n, logs.String())
	}
}

func TestLocalConsumer_AcksEventWithoutIDOrTypeWithoutHandling(t *testing.T) {
	ok := New(OrderCreated, "ord-1", "sub-1", "", 100)
	noType := ok
	noType.EventType = ""
	noType.EventID = "evt-notype"
	var mu sync.Mutex
	var acked []string
	polled := false
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		switch {
		case r.Method == "GET" && !polled:
			polled = true
			_ = json.NewEncoder(w).Encode([]Event{noType, ok})
		case r.Method == "GET":
			_, _ = io.WriteString(w, "[]")
		case r.Method == "POST":
			acked = append(acked, strings.TrimPrefix(r.URL.Path, "/ack/order/"))
			w.WriteHeader(http.StatusNoContent)
		}
	}))
	defer srv.Close()

	got := received(t, NewLocalConsumer(srv.URL, "order"), 1, 2*time.Second)
	if len(got) != 1 || got[0].EventID != ok.EventID {
		t.Errorf("handled = %+v, want only the complete event", got)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(acked) < 1 || acked[0] != "evt-notype" {
		t.Errorf("acked = %v, want evt-notype acked first", acked)
	}
}
