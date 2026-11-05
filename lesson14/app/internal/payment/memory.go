package payment

import (
	"context"
	"sync"
)

type memoryStore struct {
	mu        sync.Mutex
	byOrder   map[string]Payment
	processed map[string]bool
}

// NewMemoryStore keeps payments in process memory; for tests.
func NewMemoryStore() Store {
	return &memoryStore{byOrder: map[string]Payment{}, processed: map[string]bool{}}
}

func (s *memoryStore) Create(_ context.Context, p Payment) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.byOrder[p.OrderID]; ok {
		return ErrDuplicateOrder
	}
	s.byOrder[p.OrderID] = p
	return nil
}

func (s *memoryStore) ByOrder(_ context.Context, orderID, sub string) (Payment, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.byOrder[orderID]
	if !ok || p.CustomerSub != sub {
		return Payment{}, ErrNotFound
	}
	return p, nil
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
