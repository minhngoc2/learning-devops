package main

import (
	"context"
	"io"
	"log/slog"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
)

// Exercises the real HTTP client (events.NewLocalPublisher/NewLocalConsumer) against the bus.
func TestLocalBus_PublishPollAck(t *testing.T) {
	srv := httptest.NewServer(newBus(200 * time.Millisecond).routes(slog.New(slog.NewJSONHandler(io.Discard, nil))))
	defer srv.Close()

	e := events.New(events.OrderCreated, "ord-1", "sub-1", "", 1000)
	if err := events.NewLocalPublisher(srv.URL).Publish(context.Background(), e); err != nil {
		t.Fatalf("Publish: %v", err)
	}

	got := map[string][]events.Event{}
	for _, consumer := range []string{"payment", "order", "notification"} {
		ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
		err := events.NewLocalConsumer(srv.URL, consumer).Run(ctx, func(_ context.Context, ev events.Event) error {
			got[consumer] = append(got[consumer], ev)
			cancel()
			return nil
		})
		cancel()
		if err != nil {
			t.Fatalf("%s Run: %v", consumer, err)
		}
	}
	if len(got["payment"]) != 1 || got["payment"][0] != e || len(got["notification"]) != 1 || len(got["order"]) != 0 {
		t.Fatalf("deliveries = %+v", got)
	}

	// Acked: polling again returns nothing.
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	if err := events.NewLocalConsumer(srv.URL, "payment").Run(ctx, func(_ context.Context, ev events.Event) error {
		t.Errorf("redelivered after ack: %+v", ev)
		return nil
	}); err != nil {
		t.Fatalf("Run: %v", err)
	}
}
