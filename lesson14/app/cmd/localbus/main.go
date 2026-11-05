// Local event bus for compose: stands in for SNS + the three SQS queues. Events fan out by event_type to
// per-consumer in-memory queues with the same subscriptions as the Terraform messaging module. A polled
// event stays in flight until acked; unacked events are redelivered after 30 s. State is lost on restart.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"slices"
	"sync"
	"syscall"
	"time"

	"github.com/minhngoc2/learning-devops/lesson14/internal/config"
	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
)

var subscriptions = map[string][]string{
	"payment":      {events.OrderCreated},
	"order":        {events.PaymentSucceeded, events.PaymentFailed},
	"notification": {events.OrderCreated, events.PaymentSucceeded, events.PaymentFailed},
}

const (
	maxBatch          = 10
	visibilityTimeout = 30 * time.Second
)

type inflight struct {
	event    events.Event
	deadline time.Time
}

type queue struct {
	types    []string
	pending  []events.Event
	inflight map[string]inflight
	signal   chan struct{} // buffered(1): "pending may be non-empty"
}

type bus struct {
	mu       sync.Mutex
	queues   map[string]*queue
	longPoll time.Duration
}

func newBus(longPoll time.Duration) *bus {
	b := &bus{queues: map[string]*queue{}, longPoll: longPoll}
	for name, types := range subscriptions {
		b.queues[name] = &queue{types: types, inflight: map[string]inflight{}, signal: make(chan struct{}, 1)}
	}
	return b
}

func (b *bus) routes(log *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /health", httpx.Health())
	mux.HandleFunc("POST /publish", b.publish)
	mux.HandleFunc("GET /poll/{consumer}", b.poll)
	mux.HandleFunc("POST /ack/{consumer}/{eventId}", b.ack)
	return httpx.Logging(log, mux)
}

func (b *bus) publish(w http.ResponseWriter, r *http.Request) {
	var e events.Event
	if err := httpx.DecodeJSON(r, &e); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if e.EventID == "" || e.EventType == "" {
		httpx.WriteError(w, http.StatusBadRequest, "event_id and event_type are required")
		return
	}
	b.mu.Lock()
	var delivered []string
	for name, q := range b.queues {
		if slices.Contains(q.types, e.EventType) {
			q.pending = append(q.pending, e)
			delivered = append(delivered, name)
			select {
			case q.signal <- struct{}{}:
			default:
			}
		}
	}
	b.mu.Unlock()
	slices.Sort(delivered)
	httpx.WriteJSON(w, http.StatusAccepted, map[string]any{"event_id": e.EventID, "delivered_to": delivered})
}

// take requeues expired in-flight events, then moves up to maxBatch pending events in flight.
func (b *bus) take(q *queue) []events.Event {
	b.mu.Lock()
	defer b.mu.Unlock()
	now := time.Now()
	for id, f := range q.inflight {
		if now.After(f.deadline) {
			delete(q.inflight, id)
			q.pending = append(q.pending, f.event)
		}
	}
	n := min(len(q.pending), maxBatch)
	batch := slices.Clone(q.pending[:n])
	q.pending = q.pending[n:]
	for _, e := range batch {
		q.inflight[e.EventID] = inflight{event: e, deadline: now.Add(visibilityTimeout)}
	}
	return batch
}

func (b *bus) poll(w http.ResponseWriter, r *http.Request) {
	q, ok := b.queues[r.PathValue("consumer")]
	if !ok {
		httpx.WriteError(w, http.StatusNotFound, "unknown consumer")
		return
	}
	timer := time.NewTimer(b.longPoll)
	defer timer.Stop()
	for {
		if batch := b.take(q); len(batch) > 0 {
			httpx.WriteJSON(w, http.StatusOK, batch)
			return
		}
		select {
		case <-q.signal:
		case <-timer.C:
			httpx.WriteJSON(w, http.StatusOK, []events.Event{})
			return
		case <-r.Context().Done():
			return
		}
	}
}

func (b *bus) ack(w http.ResponseWriter, r *http.Request) {
	q, ok := b.queues[r.PathValue("consumer")]
	if !ok {
		httpx.WriteError(w, http.StatusNotFound, "unknown consumer")
		return
	}
	// Idempotent: a late ack (after the event was requeued) also drops the requeued copy.
	id := r.PathValue("eventId")
	b.mu.Lock()
	delete(q.inflight, id)
	q.pending = slices.DeleteFunc(q.pending, func(e events.Event) bool { return e.EventID == id })
	b.mu.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

func main() {
	port := config.Get("PORT", "9000")
	if httpx.HealthcheckFlag(port) {
		return
	}
	log := httpx.NewLogger()
	slog.SetDefault(log)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	srv := httpx.NewServer(":"+port, newBus(20*time.Second).routes(log))
	if err := httpx.Run(ctx, srv, log); err != nil {
		log.Error("fatal", "err", err)
		os.Exit(1)
	}
}
