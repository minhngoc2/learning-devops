package cart

import (
	"context"
	"maps"
	"sync"
	"time"
)

type memoryCart struct {
	items     map[string]int
	updatedAt time.Time
}

type memoryStore struct {
	mu    sync.Mutex
	carts map[string]memoryCart
}

// NewMemoryStore keeps carts in process memory; for tests.
func NewMemoryStore() Store { return &memoryStore{carts: map[string]memoryCart{}} }

func (s *memoryStore) Get(_ context.Context, sub string) (Cart, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c := s.carts[sub]
	return newCart(sub, c.items, c.updatedAt), nil
}

func (s *memoryStore) PutItem(_ context.Context, sub, productID string, qty int) (Cart, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c := s.carts[sub]
	c.items = maps.Clone(c.items)
	if c.items == nil {
		c.items = map[string]int{}
	}
	if qty == 0 {
		delete(c.items, productID)
	} else {
		c.items[productID] = qty
	}
	c.updatedAt = time.Now().UTC()
	s.carts[sub] = c
	return newCart(sub, c.items, c.updatedAt), nil
}

func (s *memoryStore) Clear(_ context.Context, sub string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.carts, sub)
	return nil
}
