// Small todo API backed by PostgreSQL. Config comes from env so the same image runs in compose and on ECS.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Todo struct {
	ID        int64     `json:"id"`
	Title     string    `json:"title"`
	CreatedAt time.Time `json:"created_at"`
}

// store is the slice of pgxpool the handlers need; tests swap in a fake.
type store interface {
	Ping(ctx context.Context) error
	List(ctx context.Context) ([]Todo, error)
	Create(ctx context.Context, title string) (Todo, error)
}

type pgStore struct{ pool *pgxpool.Pool }

func (s pgStore) Ping(ctx context.Context) error { return s.pool.Ping(ctx) }

func (s pgStore) List(ctx context.Context) ([]Todo, error) {
	rows, err := s.pool.Query(ctx, `SELECT id, title, created_at FROM todos ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	todos := []Todo{}
	for rows.Next() {
		var t Todo
		if err := rows.Scan(&t.ID, &t.Title, &t.CreatedAt); err != nil {
			return nil, err
		}
		todos = append(todos, t)
	}
	return todos, rows.Err()
}

func (s pgStore) Create(ctx context.Context, title string) (Todo, error) {
	t := Todo{Title: title}
	err := s.pool.QueryRow(ctx, `INSERT INTO todos (title) VALUES ($1) RETURNING id, created_at`, title).
		Scan(&t.ID, &t.CreatedAt)
	return t, err
}

func routes(s store) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /ready", func(w http.ResponseWriter, r *http.Request) {
		if err := s.Ping(r.Context()); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "db unreachable"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	})
	mux.HandleFunc("GET /todos", func(w http.ResponseWriter, r *http.Request) {
		todos, err := s.List(r.Context())
		if err != nil {
			slog.Error("list todos", "err", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
			return
		}
		writeJSON(w, http.StatusOK, todos)
	})
	mux.HandleFunc("POST /todos", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Title string `json:"title"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&in); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
			return
		}
		in.Title = strings.TrimSpace(in.Title)
		if in.Title == "" || len(in.Title) > 200 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "title must be 1-200 characters"})
			return
		}
		t, err := s.Create(r.Context(), in.Title)
		if err != nil {
			slog.Error("create todo", "err", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
			return
		}
		writeJSON(w, http.StatusCreated, t)
	})
	return mux
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func dsn() string {
	u := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(env("DB_USER", "app"), os.Getenv("DB_PASSWORD")),
		Host:     env("DB_HOST", "localhost") + ":" + env("DB_PORT", "5432"),
		Path:     env("DB_NAME", "app"),
		RawQuery: "sslmode=" + env("DB_SSLMODE", "require"),
	}
	return u.String()
}

func main() {
	healthcheck := flag.Bool("healthcheck", false, "probe /health and exit (for Docker/ECS health checks; image has no curl)")
	flag.Parse()
	port := env("PORT", "8080")

	if *healthcheck {
		resp, err := http.Get("http://127.0.0.1:" + port + "/health")
		if err != nil || resp.StatusCode != http.StatusOK {
			os.Exit(1)
		}
		os.Exit(0)
	}

	if err := run(port); err != nil {
		slog.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run(port string) error {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, dsn())
	if err != nil {
		return fmt.Errorf("db config: %w", err)
	}
	defer pool.Close()

	// ponytail: one table, so schema setup is a single idempotent statement instead of a migration tool.
	if _, err := pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS todos (
		id         BIGSERIAL PRIMARY KEY,
		title      TEXT NOT NULL,
		created_at TIMESTAMPTZ NOT NULL DEFAULT now())`); err != nil {
		return fmt.Errorf("db init: %w", err)
	}

	srv := &http.Server{Addr: ":" + port, Handler: routes(pgStore{pool}), ReadHeaderTimeout: 5 * time.Second}
	go func() {
		<-ctx.Done() // ECS sends SIGTERM before stopping the task
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		srv.Shutdown(shutdownCtx)
	}()

	slog.Info("listening", "port", port)
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}
