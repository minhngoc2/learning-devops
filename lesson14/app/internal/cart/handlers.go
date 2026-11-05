package cart

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
)

const maxProductIDLen = 128

// Routes mounts GET /api/cart, PUT /api/cart/items/{productId}, DELETE /api/cart (all need an identity)
// and GET /health.
func Routes(s Store, log *slog.Logger) http.Handler {
	h := handlers{store: s, log: log}
	mux := http.NewServeMux()
	mux.Handle("GET /health", httpx.Health())
	mux.Handle("GET /api/cart", httpx.RequireIdentity(http.HandlerFunc(h.get)))
	mux.Handle("PUT /api/cart/items/{productId}", httpx.RequireIdentity(http.HandlerFunc(h.putItem)))
	mux.Handle("DELETE /api/cart", httpx.RequireIdentity(http.HandlerFunc(h.clear)))
	return httpx.Logging(log, mux)
}

type handlers struct {
	store Store
	log   *slog.Logger
}

func (h handlers) get(w http.ResponseWriter, r *http.Request) {
	id, _ := httpx.IdentityFrom(r)
	c, err := h.store.Get(r.Context(), id.Sub)
	if err != nil {
		httpx.Internal(w, h.log, "get cart", err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, c)
}

func (h handlers) putItem(w http.ResponseWriter, r *http.Request) {
	id, _ := httpx.IdentityFrom(r)
	productID := r.PathValue("productId")
	if len(productID) > maxProductIDLen {
		httpx.WriteError(w, http.StatusBadRequest, "product id is too long")
		return
	}

	var in struct {
		Quantity json.RawMessage `json:"quantity"`
	}
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	qty, ok := parseQuantity(in.Quantity)
	if !ok {
		httpx.WriteError(w, http.StatusBadRequest, "quantity must be an integer from 0 to 99")
		return
	}

	c, err := h.store.PutItem(r.Context(), id.Sub, productID, qty)
	if err != nil {
		httpx.Internal(w, h.log, "put cart item", err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, c)
}

func (h handlers) clear(w http.ResponseWriter, r *http.Request) {
	id, _ := httpx.IdentityFrom(r)
	if err := h.store.Clear(r.Context(), id.Sub); err != nil {
		httpx.Internal(w, h.log, "clear cart", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// parseQuantity accepts only a bare JSON integer in [0, MaxQuantity]: strings ("two"), fractions (1.5),
// exponents (1e1), null and a missing field are rejected.
func parseQuantity(raw json.RawMessage) (int, bool) {
	q, err := strconv.Atoi(string(raw))
	if err != nil || q < 0 || q > MaxQuantity {
		return 0, false
	}
	return q, true
}
