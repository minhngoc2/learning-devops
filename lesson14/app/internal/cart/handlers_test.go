package cart

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func do(h http.Handler, method, path, body, sub string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	if sub != "" {
		r.Header.Set("X-Customer-Sub", sub)
		r.Header.Set("X-Customer-Email", sub+"@example.com")
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	return rec
}

func newHandler() http.Handler {
	return Routes(NewMemoryStore(), slog.New(slog.NewJSONHandler(io.Discard, nil)))
}

func TestGetCart_EmptyIsEmptyList(t *testing.T) {
	rec := do(newHandler(), "GET", "/api/cart", "", "sub-1")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"customer_sub":"sub-1","items":[]}` {
		t.Errorf("body = %s", got)
	}
}

func TestPutItem_QuantityRules(t *testing.T) {
	cases := []struct {
		name, body string
		want       int
		wantItems  string
	}{
		{"three sets the line", `{"quantity":3}`, 200, `"items":[{"product_id":"p-1","quantity":3}]`},
		{"zero removes the line", `{"quantity":0}`, 200, `"items":[]`},
		{"negative", `{"quantity":-1}`, 400, ""},
		{"above 99", `{"quantity":100}`, 400, ""},
		{"not an integer", `{"quantity":"two"}`, 400, ""},
		{"fraction", `{"quantity":1.5}`, 400, ""},
		{"missing", `{}`, 400, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			h := newHandler()
			if rec := do(h, "PUT", "/api/cart/items/p-1", `{"quantity":2}`, "sub-1"); rec.Code != 200 {
				t.Fatalf("seed: status %d", rec.Code)
			}
			rec := do(h, "PUT", "/api/cart/items/p-1", c.body, "sub-1")
			if rec.Code != c.want {
				t.Fatalf("status = %d, want %d (body %s)", rec.Code, c.want, rec.Body)
			}
			body := rec.Body.String()
			if c.want == 200 && !strings.Contains(body, c.wantItems) {
				t.Errorf("body = %s, want it to contain %s", body, c.wantItems)
			}
			if c.want == 400 {
				if !strings.HasPrefix(body, `{"error":`) {
					t.Errorf("body = %s, want error JSON", body)
				}
				// A rejected update leaves the cart unchanged.
				if got := do(h, "GET", "/api/cart", "", "sub-1").Body.String(); !strings.Contains(got, `"quantity":2`) {
					t.Errorf("cart after rejected update = %s", got)
				}
			}
		})
	}
}

func TestDeleteCart_204(t *testing.T) {
	h := newHandler()
	do(h, "PUT", "/api/cart/items/p-1", `{"quantity":1}`, "sub-1")

	if rec := do(h, "DELETE", "/api/cart", "", "sub-1"); rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	if got := strings.TrimSpace(do(h, "GET", "/api/cart", "", "sub-1").Body.String()); got != `{"customer_sub":"sub-1","items":[]}` {
		t.Errorf("cart after delete = %s", got)
	}
}

func TestCart_Unauthenticated401(t *testing.T) {
	h := newHandler()
	for _, r := range []struct{ method, path, body string }{
		{"GET", "/api/cart", ""},
		{"PUT", "/api/cart/items/p-1", `{"quantity":1}`},
		{"DELETE", "/api/cart", ""},
	} {
		if rec := do(h, r.method, r.path, r.body, ""); rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s: status = %d, want 401", r.method, r.path, rec.Code)
		}
	}
	if rec := do(h, "GET", "/health", "", ""); rec.Code != http.StatusOK {
		t.Errorf("GET /health: status = %d, want 200", rec.Code)
	}
}
