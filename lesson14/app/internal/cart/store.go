// Package cart is the Cart Service: one DynamoDB item per customer holding product id → quantity.
package cart

import (
	"context"
	"errors"
	"slices"
	"strings"
	"time"
)

// MaxQuantity is the largest quantity a cart line may hold; 0 removes the line.
const MaxQuantity = 99

// MaxLines caps the distinct products in one cart; it keeps the DynamoDB item and a checkout's ?ids= lookup bounded.
const MaxLines = 100

// ErrCartFull is returned by PutItem when a new product would exceed MaxLines.
var ErrCartFull = errors.New("cart is full (max 100 lines)")

type Item struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

// Cart is what GET /api/cart returns. Items is never nil, so an empty cart encodes as "items":[].
type Cart struct {
	CustomerSub string    `json:"customer_sub"`
	Items       []Item    `json:"items"`
	UpdatedAt   time.Time `json:"updated_at,omitzero"`
}

// Store persists carts. PutItem sets a line's quantity (qty 0 removes it) and returns the updated cart;
// callers validate 0 <= qty <= MaxQuantity first. Adding a product to a cart that already has MaxLines lines
// returns ErrCartFull. Clear removes the whole cart and succeeds if none exists.
type Store interface {
	Get(ctx context.Context, sub string) (Cart, error)
	PutItem(ctx context.Context, sub, productID string, qty int) (Cart, error)
	Clear(ctx context.Context, sub string) error
}

// newCart turns a product id → quantity map into a Cart with lines sorted by product id.
func newCart(sub string, items map[string]int, updatedAt time.Time) Cart {
	c := Cart{CustomerSub: sub, Items: make([]Item, 0, len(items)), UpdatedAt: updatedAt}
	for id, q := range items {
		if q > 0 {
			c.Items = append(c.Items, Item{ProductID: id, Quantity: q})
		}
	}
	slices.SortFunc(c.Items, func(a, b Item) int { return strings.Compare(a.ProductID, b.ProductID) })
	return c
}
