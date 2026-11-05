// Package httpx holds the HTTP plumbing every service shares: server lifecycle, JSON, identity and logging.
package httpx

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"
)

// NewServer returns a server with timeouts set. WriteTimeout leaves room for 20 s long polls.
func NewServer(addr string, h http.Handler) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           h,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
}

// Run serves until ctx is cancelled (ECS sends SIGTERM), then drains in-flight requests for up to 10 s.
func Run(ctx context.Context, srv *http.Server, log *slog.Logger) error {
	errc := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", srv.Addr)
		errc <- srv.ListenAndServe()
	}()

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}

	log.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return err
	}
	if err := <-errc; !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

// HealthcheckFlag parses the command line. Without -healthcheck it returns false. With it, it probes
// http://127.0.0.1:<port>/health (the distroless image has no curl): it exits 1 on failure and returns
// true on success, so main can simply return.
func HealthcheckFlag(port string) (handled bool) {
	if flag.Lookup("healthcheck") == nil {
		flag.Bool("healthcheck", false, "probe /health and exit (for Docker/ECS health checks)")
	}
	if !flag.Parsed() {
		flag.Parse()
	}
	if flag.Lookup("healthcheck").Value.String() != "true" {
		return false
	}

	client := http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get("http://127.0.0.1:" + port + "/health")
	if err != nil {
		os.Exit(1)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		os.Exit(1)
	}
	return true
}

// NewLogger returns a JSON logger on stdout at the level in LOG_LEVEL (debug, info, warn, error; default info).
// Logging adds service to request lines; each service's log group already identifies the rest.
func NewLogger() *slog.Logger {
	var level slog.Level
	if err := level.UnmarshalText([]byte(strings.TrimSpace(os.Getenv("LOG_LEVEL")))); err != nil {
		level = slog.LevelInfo
	}
	return slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level}))
}

// Health answers 200 {"status":"ok"} for ALB, ECS and Docker health checks.
func Health() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
}
