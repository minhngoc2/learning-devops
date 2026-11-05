package order

import (
	"cmp"
	"context"
	"slices"
	"sync"
	"time"
)

type memoryStore struct {
	mu        sync.Mutex
	orders    map[string]Order
	processed map[string]bool
}

// NewMemoryStore keeps orders in process memory; for tests.
func NewMemoryStore() Store {
	return &memoryStore{orders: map[string]Order{}, processed: map[string]bool{}}
}

func (s *memoryStore) Create(_ context.Context, o Order) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	o.Items = slices.Clone(o.Items)
	s.orders[o.ID] = o
	return nil
}

func (s *memoryStore) Get(_ context.Context, id, sub string) (Order, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	o, ok := s.orders[id]
	if !ok || o.CustomerSub != sub {
		return Order{}, ErrNotFound
	}
	o.Items = slices.Clone(o.Items)
	return o, nil
}

func (s *memoryStore) List(_ context.Context, sub string) ([]Order, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []Order{}
	for _, o := range s.orders {
		if o.CustomerSub == sub {
			o.Items = slices.Clone(o.Items)
			out = append(out, o)
		}
	}
	slices.SortFunc(out, func(a, b Order) int { return cmp.Or(b.CreatedAt.Compare(a.CreatedAt), cmp.Compare(a.ID, b.ID)) })
	return out, nil
}

func (s *memoryStore) SetStatus(_ context.Context, id string, st Status) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	o, ok := s.orders[id]
	if !ok {
		return ErrNotFound
	}
	if o.Status != PendingPayment {
		return ErrNotPending
	}
	o.Status = st
	o.UpdatedAt = time.Now().UTC()
	s.orders[id] = o
	return nil
}

func (s *memoryStore) MarkProcessed(_ context.Context, eventID string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.processed[eventID] {
		return false, nil
	}
	s.processed[eventID] = true
	return true, nil
}
