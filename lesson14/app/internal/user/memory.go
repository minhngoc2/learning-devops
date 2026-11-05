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

func (s *memoryStore) Create(_ context.Context, c Customer) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.customers[c.Sub]; ok {
		return false, nil
	}
	s.customers[c.Sub] = c
	return true, nil
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
