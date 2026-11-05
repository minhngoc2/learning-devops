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

// Store persists Customers. Create inserts the row unless one with the same sub exists and reports whether
// it did; an existing row is left untouched (SignUp does not check the password, so a repeated register
// must not be able to rewrite someone's profile).
type Store interface {
	Create(ctx context.Context, c Customer) (created bool, err error)
	Get(ctx context.Context, sub string) (Customer, error)
}
