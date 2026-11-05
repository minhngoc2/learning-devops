package user

import (
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
)

// Routes mounts POST /api/users/register (201 Customer; 409 for a taken email), POST /api/users/login
// (200 Tokens; 401 for bad credentials), GET /api/users/me (needs an identity; 404 without a profile row)
// and GET /health. Emails are trimmed and lower-cased before they reach Auth or the Store.
func Routes(a Auth, s Store, log *slog.Logger) http.Handler {
	h := handlers{auth: a, store: s, log: log}
	mux := http.NewServeMux()
	mux.Handle("GET /health", httpx.Health())
	mux.HandleFunc("POST /api/users/register", h.register)
	mux.HandleFunc("POST /api/users/login", h.login)
	mux.Handle("GET /api/users/me", httpx.RequireIdentity(http.HandlerFunc(h.me)))
	return httpx.Logging(log, mux)
}

type handlers struct {
	auth  Auth
	store Store
	log   *slog.Logger
}

func normalizeEmail(s string) string { return strings.ToLower(strings.TrimSpace(s)) }

func (h handlers) register(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email       string `json:"email"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
	}
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	email, name := normalizeEmail(req.Email), strings.TrimSpace(req.DisplayName)
	switch {
	case !strings.Contains(email, "@"):
		httpx.WriteError(w, http.StatusBadRequest, "a valid email is required")
		return
	case req.Password == "":
		httpx.WriteError(w, http.StatusBadRequest, "password is required")
		return
	case name == "":
		httpx.WriteError(w, http.StatusBadRequest, "display_name is required")
		return
	}

	sub, err := h.auth.Register(r.Context(), email, req.Password, name)
	switch {
	case errors.Is(err, ErrEmailTaken):
		httpx.WriteError(w, http.StatusConflict, "email already registered")
		return
	case errors.Is(err, ErrInvalidInput):
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	case err != nil:
		h.internal(w, "register", err)
		return
	}
	c := Customer{Sub: sub, Email: email, DisplayName: name, CreatedAt: time.Now().UTC()}
	if err := h.store.Create(r.Context(), c); err != nil {
		h.internal(w, "store customer", err)
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, c)
}

func (h handlers) login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	tok, err := h.auth.Login(r.Context(), normalizeEmail(req.Email), req.Password)
	switch {
	case err == nil:
		httpx.WriteJSON(w, http.StatusOK, tok)
	case errors.Is(err, ErrInvalidCredentials):
		httpx.WriteError(w, http.StatusUnauthorized, "invalid credentials")
	default:
		h.internal(w, "login", err)
	}
}

func (h handlers) me(w http.ResponseWriter, r *http.Request) {
	id, _ := httpx.IdentityFrom(r)
	c, err := h.store.Get(r.Context(), id.Sub)
	switch {
	case err == nil:
		httpx.WriteJSON(w, http.StatusOK, c)
	case errors.Is(err, ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "customer not found")
	default:
		h.internal(w, "get customer", err)
	}
}

func (h handlers) internal(w http.ResponseWriter, msg string, err error) {
	h.log.Error(msg, "err", err)
	httpx.WriteError(w, http.StatusInternalServerError, "internal error")
}
