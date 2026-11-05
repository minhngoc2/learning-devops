package product

import (
	"cmp"
	"context"
	"slices"
	"sync"
)

type memoryStore struct {
	mu       sync.Mutex
	products map[string]Product
}

// NewMemoryStore keeps products in process memory; for tests.
func NewMemoryStore() Store { return &memoryStore{products: map[string]Product{}} }

func (s *memoryStore) List(_ context.Context) ([]Product, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []Product{}
	for _, p := range s.products {
		out = append(out, p)
	}
	slices.SortFunc(out, func(a, b Product) int { return cmp.Compare(a.ID, b.ID) })
	return out, nil
}

func (s *memoryStore) ByIDs(ctx context.Context, ids []string) ([]Product, error) {
	all, _ := s.List(ctx)
	return slices.DeleteFunc(all, func(p Product) bool { return !slices.Contains(ids, p.ID) }), nil
}

func (s *memoryStore) Get(_ context.Context, id string) (Product, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.products[id]
	if !ok {
		return Product{}, ErrNotFound
	}
	return p, nil
}

func (s *memoryStore) Create(_ context.Context, p Product) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.products[p.ID]; ok {
		return ErrDuplicate
	}
	s.products[p.ID] = p
	return nil
}
