package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type fakeStore struct {
	todos   []Todo
	pingErr error
}

func (f *fakeStore) Ping(context.Context) error           { return f.pingErr }
func (f *fakeStore) List(context.Context) ([]Todo, error) { return f.todos, nil }
func (f *fakeStore) Create(_ context.Context, title string) (Todo, error) {
	t := Todo{ID: int64(len(f.todos) + 1), Title: title, CreatedAt: time.Now()}
	f.todos = append(f.todos, t)
	return t, nil
}

func TestRoutes(t *testing.T) {
	fs := &fakeStore{}
	h := routes(fs)
	cases := []struct {
		method, path, body string
		want               int
	}{
		{"GET", "/health", "", 200},
		{"GET", "/ready", "", 200},
		{"POST", "/todos", `{"title":"  "}`, 400},
		{"POST", "/todos", `not json`, 400},
		{"POST", "/todos", `{"title":"learn ecs"}`, 201},
		{"GET", "/todos", "", 200},
		{"DELETE", "/todos", "", 405},
	}
	for _, c := range cases {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(c.method, c.path, strings.NewReader(c.body)))
		if rec.Code != c.want {
			t.Errorf("%s %s: got %d, want %d", c.method, c.path, rec.Code, c.want)
		}
	}
	if len(fs.todos) != 1 || fs.todos[0].Title != "learn ecs" {
		t.Errorf("store = %+v, want one todo", fs.todos)
	}

	fs.pingErr = errors.New("down")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/ready", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("/ready with db down: got %d, want 503", rec.Code)
	}
}
