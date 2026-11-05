package events

import (
	"context"
	"slices"
	"sync"
	"time"
)

// MemoryBus is an in-process bus for tests. Each consumer gets its own queue holding the event types it
// subscribed to, like an SQS queue behind an SNS filter policy. A handler error requeues the event.
type MemoryBus struct {
	mu     sync.Mutex
	queues []*memoryQueue
}

type memoryQueue struct {
	name   string
	types  []string
	mu     sync.Mutex
	events []Event
	signal chan struct{} // buffered(1): "the queue may be non-empty"
}

func NewMemoryBus() *MemoryBus { return &MemoryBus{} }

// Consumer subscribes a named consumer to types. Only events published after this call are delivered.
func (b *MemoryBus) Consumer(consumer string, types []string) Consumer {
	q := &memoryQueue{name: consumer, types: slices.Clone(types), signal: make(chan struct{}, 1)}
	b.mu.Lock()
	b.queues = append(b.queues, q)
	b.mu.Unlock()
	return q
}

func (b *MemoryBus) Publish(_ context.Context, e Event) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	for _, q := range b.queues {
		if slices.Contains(q.types, e.EventType) {
			q.push(e)
		}
	}
	return nil
}

func (q *memoryQueue) push(e Event) {
	q.mu.Lock()
	q.events = append(q.events, e)
	q.mu.Unlock()
	select {
	case q.signal <- struct{}{}:
	default:
	}
}

func (q *memoryQueue) pop() (Event, bool) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.events) == 0 {
		return Event{}, false
	}
	e := q.events[0]
	q.events = q.events[1:]
	return e, true
}

func (q *memoryQueue) Run(ctx context.Context, h Handler) error {
	for {
		e, ok := q.pop()
		if !ok {
			select {
			case <-ctx.Done():
				return nil
			case <-q.signal:
				continue
			}
		}
		if err := h(ctx, e); err != nil {
			q.push(e)
			select { // brief pause so a failing handler does not spin
			case <-ctx.Done():
				return nil
			case <-time.After(10 * time.Millisecond):
			}
		}
		if ctx.Err() != nil {
			return nil
		}
	}
}
