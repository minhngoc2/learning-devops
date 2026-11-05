package user

import (
	"context"
	"sync"

	"github.com/google/uuid"
)

type localAccount struct{ sub, password string }

type localAuth struct {
	mu       sync.Mutex
	accounts map[string]localAccount // email → account
}

// NewLocalAuth is the AUTH_MODE=local stand-in for Cognito: accounts live in process memory (lost on
// restart) and the tokens are unsigned "local:<sub>:<email>" strings. Compose only; never on AWS.
func NewLocalAuth() Auth { return &localAuth{accounts: map[string]localAccount{}} }

func (a *localAuth) Register(_ context.Context, email, password, _ string) (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if _, ok := a.accounts[email]; ok {
		return "", ErrEmailTaken
	}
	sub := uuid.NewString()
	a.accounts[email] = localAccount{sub: sub, password: password}
	return sub, nil
}

func (a *localAuth) Login(_ context.Context, email, password string) (Tokens, error) {
	a.mu.Lock()
	acc, ok := a.accounts[email]
	a.mu.Unlock()
	if !ok || acc.password != password {
		return Tokens{}, ErrInvalidCredentials
	}
	token := "local:" + acc.sub + ":" + email
	return Tokens{IDToken: token, AccessToken: token, ExpiresIn: 3600}, nil
}
