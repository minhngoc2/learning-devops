package payment

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
)

// Routes mounts GET /api/payments/{orderId} (needs an identity; 404 when there is no payment yet or it is
// another customer's) and GET /health.
func Routes(s *Service, log *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /health", httpx.Health())
	mux.Handle("GET /api/payments/{orderId}", httpx.RequireIdentity(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id, _ := httpx.IdentityFrom(r)
		p, err := s.ByOrder(r.Context(), r.PathValue("orderId"), id.Sub)
		switch {
		case err == nil:
			httpx.WriteJSON(w, http.StatusOK, p)
		case errors.Is(err, ErrNotFound):
			httpx.WriteError(w, http.StatusNotFound, "payment not found")
		default:
			log.Error("get payment", "err", err)
			httpx.WriteError(w, http.StatusInternalServerError, "internal error")
		}
	})))
	return httpx.Logging(log, mux)
}
