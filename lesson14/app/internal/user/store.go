// Package user is the User Service: it registers and signs in Customers through Cognito (or an in-memory
// stand-in locally) and keeps their profile row in the users schema, keyed by the Cognito sub.
package user

import (
	"context"
	"errors"
	"time"
)

// Customer is the profile row; Sub is the Cognito user id that API Gateway passes as X-Customer-Sub.
type Customer struct {
	Sub         string    `json:"sub"`
	Email       string    `json:"email"`
	DisplayName string    `json:"display_name"`
	CreatedAt   time.Time `json:"created_at"`
}

var ErrNotFound = errors.New("customer not found")

// Store persists Customers. Create overwrites an existing row with the same sub, so a retried register
// cannot get stuck on a half-written profile.
type Store interface {
	Create(ctx context.Context, c Customer) error
	Get(ctx context.Context, sub string) (Customer, error)
}
