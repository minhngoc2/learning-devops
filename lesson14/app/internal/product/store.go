// Package product is the Product Service: the catalogue that the storefront lists and Order Service
// snapshots at checkout. Images live in S3 and are uploaded by the seed script; the service only stores keys.
package product

import (
	"context"
	"errors"
	"time"
)

// Product is one catalogue entry. ImageKey is the S3 key under the images bucket (products/<id>.png);
// the API adds image_url built from PUBLIC_BASE_URL.
type Product struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	PriceCents  int64     `json:"price_cents"`
	Currency    string    `json:"currency"`
	Category    string    `json:"category"`
	ImageKey    string    `json:"image_key"`
	CreatedAt   time.Time `json:"created_at"`
}

var (
	ErrNotFound  = errors.New("product not found")
	ErrDuplicate = errors.New("product already exists")
)

// Store persists products in the products schema. List and ByIDs return products ordered by id (never nil);
// ByIDs skips ids it does not know. Create returns ErrDuplicate when the id exists.
type Store interface {
	List(ctx context.Context) ([]Product, error)
	ByIDs(ctx context.Context, ids []string) ([]Product, error)
	Get(ctx context.Context, id string) (Product, error)
	Create(ctx context.Context, p Product) error
}
