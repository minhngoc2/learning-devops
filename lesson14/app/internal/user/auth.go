package user

import (
	"context"
	"errors"
)

// Tokens is what login returns; the storefront sends IDToken as the Bearer token.
type Tokens struct {
	IDToken      string `json:"id_token"`
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int32  `json:"expires_in"`
}

var (
	ErrEmailTaken         = errors.New("email already registered")
	ErrInvalidCredentials = errors.New("invalid credentials")
	// ErrInvalidInput wraps the identity provider's rejection of an email or password (e.g. password policy).
	ErrInvalidInput = errors.New("invalid registration")
)

// Auth creates and signs in identities. Register returns the new sub (ErrEmailTaken if the email exists);
// Login returns ErrInvalidCredentials for an unknown email or a wrong password.
type Auth interface {
	Register(ctx context.Context, email, password, displayName string) (sub string, err error)
	Login(ctx context.Context, email, password string) (Tokens, error)
}
