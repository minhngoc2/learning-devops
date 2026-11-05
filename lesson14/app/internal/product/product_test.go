package product

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"
)

const base = "https://cdn.example.com"

func routes(s Store) http.Handler {
	return Routes(s, base, slog.New(slog.NewJSONHandler(io.Discard, nil)))
}

func seeded(t *testing.T) Store {
	t.Helper()
	s := NewMemoryStore()
	for _, p := range []Product{
		{ID: "p-0001", Name: "Mug", PriceCents: 15000, Currency: "VND", Category: "kitchen", ImageKey: "products/p-0001.png"},
		{ID: "p-0002", Name: "Tee", PriceCents: 25000, Currency: "VND", Category: "apparel"},
		{ID: "p-0003", Name: "Cap", PriceCents: 12000, Currency: "VND", Category: "apparel"},
	} {
		p.CreatedAt = time.Now().UTC()
		if err := s.Create(context.Background(), p); err != nil {
			t.Fatalf("seed: %v", err)
		}
	}
	return s
}

func do(h http.Handler, method, path, sub, body string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	if sub != "" {
		r.Header.Set("X-Customer-Sub", sub)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	return rec
}

func listIDs(t *testing.T, rec *httptest.ResponseRecorder) []string {
	t.Helper()
	var list []map[string]any
	if err := json.NewDecoder(rec.Body).Decode(&list); err != nil {
		t.Fatalf("decode: %v", err)
	}
	out := []string{}
	for _, p := range list {
		out = append(out, p["id"].(string))
	}
	return out
}

func TestList_ByIDs(t *testing.T) {
	h := routes(seeded(t))

	rec := do(h, "GET", "/api/products?ids=p-0003,p-0001,p-9999", "", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	if got := strings.Join(listIDs(t, rec), ","); got != "p-0001,p-0003" {
		t.Errorf("ids filter = %s, want p-0001,p-0003 (unknown absent)", got)
	}

	if got := strings.Join(listIDs(t, do(h, "GET", "/api/products", "", "")), ","); got != "p-0001,p-0002,p-0003" {
		t.Errorf("full list = %s", got)
	}
	if got := strings.Join(listIDs(t, do(h, "GET", "/api/products?category=apparel", "", "")), ","); got != "p-0002,p-0003" {
		t.Errorf("category filter = %s", got)
	}
	if got := listIDs(t, do(h, "GET", "/api/products?ids=p-9999", "", "")); len(got) != 0 {
		t.Errorf("unknown only = %v, want []", got)
	}

	// The shape Order Service decodes.
	var list []map[string]any
	_ = json.NewDecoder(do(h, "GET", "/api/products?ids=p-0001", "", "").Body).Decode(&list)
	for _, k := range []string{"id", "name", "description", "price_cents", "currency", "category", "image_url"} {
		if _, ok := list[0][k]; !ok {
			t.Errorf("missing key %q in %v", k, list[0])
		}
	}
	if list[0]["image_url"] != base+"/images/products/p-0001.png" {
		t.Errorf("image_url = %v", list[0]["image_url"])
	}
}

func TestGet_404(t *testing.T) {
	h := routes(seeded(t))

	rec := do(h, "GET", "/api/products/p-9999", "", "")
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"product not found"}` {
		t.Errorf("body = %s", got)
	}

	rec = do(h, "GET", "/api/products/p-0002", "", "")
	var p map[string]any
	_ = json.NewDecoder(rec.Body).Decode(&p)
	if rec.Code != http.StatusOK || p["name"] != "Tee" || p["image_url"] != "" {
		t.Errorf("get p-0002 = %d %v (image_url must be empty without a key)", rec.Code, p)
	}
}

func TestCreate_ValidationAndImageURL(t *testing.T) {
	h := routes(NewMemoryStore())

	for _, body := range []string{
		`{"name":"Mug","price_cents":0,"currency":"VND"}`,
		`{"name":"Mug","price_cents":-5,"currency":"VND"}`,
		`{"name":"","price_cents":100,"currency":"VND"}`,
		`{"name":"Mug","price_cents":100,"currency":""}`,
		`{"name":"Mug","price_cents":100,"currency":"vnd"}`,
		`{"id":"bad id","name":"Mug","price_cents":100,"currency":"VND"}`,
		`not json`,
	} {
		if rec := do(h, "POST", "/api/products", "sub-1", body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s → %d, want 400", body, rec.Code)
		}
	}

	rec := do(h, "POST", "/api/products", "sub-1",
		`{"name":"Mug","description":"Big","price_cents":1999,"currency":"VND","category":"kitchen","image_key":"products/p-x.png"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create status = %d (%s)", rec.Code, rec.Body)
	}
	var got map[string]any
	_ = json.NewDecoder(rec.Body).Decode(&got)
	id, _ := got["id"].(string)
	if !regexp.MustCompile(`^p-[0-9a-f]{8}$`).MatchString(id) {
		t.Errorf("id = %q, want p-<8 hex>", id)
	}
	if got["image_url"] != base+"/images/products/p-x.png" || got["price_cents"] != float64(1999) || got["name"] != "Mug" {
		t.Errorf("created = %v", got)
	}
	if rec := do(h, "GET", "/api/products/"+id, "", ""); rec.Code != http.StatusOK {
		t.Errorf("created product not readable: %d", rec.Code)
	}

	// Seed ids are kept; a second create with the same id conflicts.
	body := `{"id":"p-0001","name":"Tee","price_cents":2500,"currency":"VND"}`
	rec = do(h, "POST", "/api/products", "sub-1", body)
	_ = json.NewDecoder(rec.Body).Decode(&got)
	if rec.Code != http.StatusCreated || got["id"] != "p-0001" || got["image_url"] != "" {
		t.Errorf("explicit id: %d %v", rec.Code, got)
	}
	if rec := do(h, "POST", "/api/products", "sub-1", body); rec.Code != http.StatusConflict {
		t.Errorf("duplicate id → %d, want 409", rec.Code)
	}
}

func TestCreate_Unauthenticated401(t *testing.T) {
	s := NewMemoryStore()
	rec := do(routes(s), "POST", "/api/products", "", `{"name":"Mug","price_cents":100,"currency":"VND"}`)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
	if list, _ := s.List(context.Background()); len(list) != 0 {
		t.Errorf("stored %v, want nothing", list)
	}
}

func TestCreate_CurrencyMustBeVND(t *testing.T) {
	s := NewMemoryStore()
	rec := do(routes(s), "POST", "/api/products", "sub-1", `{"name":"Mug","price_cents":100,"currency":"USD"}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"currency must be VND"}` {
		t.Errorf("body = %s", got)
	}
	if list, _ := s.List(context.Background()); len(list) != 0 {
		t.Errorf("stored %v, want nothing", list)
	}
}

func TestList_IDsCappedAt100Distinct(t *testing.T) {
	h := routes(seeded(t))
	idList := func(n int, extra ...string) string {
		out := []string{}
		for i := range n {
			out = append(out, fmt.Sprintf("p-%04d", i+1))
		}
		return strings.Join(append(out, extra...), ",")
	}

	// 100 distinct ids plus repeats is fine.
	rec := do(h, "GET", "/api/products?ids="+idList(100, "p-0001", "p-0002"), "", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("100 distinct: status = %d (%s)", rec.Code, rec.Body)
	}
	if got := strings.Join(listIDs(t, rec), ","); got != "p-0001,p-0002,p-0003" {
		t.Errorf("100 distinct = %s", got)
	}

	rec = do(h, "GET", "/api/products?ids="+idList(101), "", "")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("101 distinct: status = %d, want 400", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"too many ids (max 100)"}` {
		t.Errorf("body = %s", got)
	}
}
