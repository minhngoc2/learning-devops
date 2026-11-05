package httpx

import (
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/google/uuid"
)

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Unwrap() http.ResponseWriter { return s.ResponseWriter }

// Logging logs one line per request with request_id, service and customer_sub. It reuses an incoming
// X-Request-Id (or generates one) and echoes it in the response. Health checks log at debug level.
func Logging(log *slog.Logger, next http.Handler) http.Handler {
	service := os.Getenv("SERVICE")
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		requestID := r.Header.Get("X-Request-Id")
		if requestID == "" {
			requestID = uuid.NewString()
		}
		w.Header().Set("X-Request-Id", requestID)

		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		level := slog.LevelInfo
		if r.URL.Path == "/health" {
			level = slog.LevelDebug
		}
		log.Log(r.Context(), level, "request",
			"request_id", requestID,
			"service", service,
			"customer_sub", r.Header.Get("X-Customer-Sub"),
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	})
}
