package order

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
)

// Routes mounts POST /api/orders (checkout, 201), GET /api/orders, GET /api/orders/{id} (404 unless the
// caller owns it), all needing an identity, and GET /health.
func Routes(s *Service, log *slog.Logger) http.Handler {
	h := handlers{svc: s, log: log}
	mux := http.NewServeMux()
	mux.Handle("GET /health", httpx.Health())
	mux.Handle("POST /api/orders", httpx.RequireIdentity(http.HandlerFunc(h.checkout)))
	mux.Handle("GET /api/orders", httpx.RequireIdentity(http.HandlerFunc(h.list)))
	mux.Handle("GET /api/orders/{id}", httpx.RequireIdentity(http.HandlerFunc(h.get)))
	return httpx.Logging(log, mux)
}

type handlers struct {
	svc *Service
	log *slog.Logger
}

func (h handlers) checkout(w http.ResponseWriter, r *http.Request) {
	id, _ := httpx.IdentityFrom(r)
	o, err := h.svc.Checkout(r.Context(), id)
	var unknown ErrUnknownProduct
	switch {
	case err == nil:
		httpx.WriteJSON(w, http.StatusCreated, o)
	case errors.Is(err, ErrEmptyCart), errors.As(err, &unknown):
		httpx.WriteError(w, http.StatusUnprocessableEntity, err.Error())
	default:
		httpx.Internal(w, h.log, "checkout", err)
	}
}

func (h handlers) list(w http.ResponseWriter, r *http.Request) {
	id, _ := httpx.IdentityFrom(r)
	orders, err := h.svc.List(r.Context(), id.Sub)
	if err != nil {
		httpx.Internal(w, h.log, "list orders", err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, orders)
}

func (h handlers) get(w http.ResponseWriter, r *http.Request) {
	id, _ := httpx.IdentityFrom(r)
	o, err := h.svc.Get(r.Context(), r.PathValue("id"), id.Sub)
	switch {
	case err == nil:
		httpx.WriteJSON(w, http.StatusOK, o)
	case errors.Is(err, ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "order not found")
	default:
		httpx.Internal(w, h.log, "get order", err)
	}
}
