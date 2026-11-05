package user

import (
	"context"
	"sync"
)

type memoryStore struct {
	mu        sync.Mutex
	customers map[string]Customer
}

// NewMemoryStore keeps Customers in process memory; for tests.
func NewMemoryStore() Store { return &memoryStore{customers: map[string]Customer{}} }

func (s *memoryStore) Create(_ context.Context, c Customer) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.customers[c.Sub] = c
	return nil
}

func (s *memoryStore) Get(_ context.Context, sub string) (Customer, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c, ok := s.customers[sub]
	if !ok {
		return Customer{}, ErrNotFound
	}
	return c, nil
}
