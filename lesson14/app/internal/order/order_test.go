package order

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
)

// calls records the order of side effects across the fakes ("publish", "clear").
type calls struct {
	mu  sync.Mutex
	log []string
}

func (c *calls) add(s string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.log = append(c.log, s)
}

type fakeCart struct {
	items    map[string][]cartItem
	clearErr error
	cleared  []string
	calls    *calls
}

func (f *fakeCart) Get(_ context.Context, sub string) ([]cartItem, error) { return f.items[sub], nil }

func (f *fakeCart) Clear(_ context.Context, sub string) error {
	f.calls.add("clear")
	if f.clearErr != nil {
		return f.clearErr
	}
	f.cleared = append(f.cleared, sub)
	return nil
}

type fakeProducts struct{ products map[string]product }

func (f *fakeProducts) ByIDs(_ context.Context, ids []string) (map[string]product, error) {
	out := map[string]product{}
	for _, id := range ids {
		if p, ok := f.products[id]; ok {
			out[id] = p
		}
	}
	return out, nil
}

type fakePublisher struct {
	published []events.Event
	calls     *calls
}

func (f *fakePublisher) Publish(_ context.Context, e events.Event) error {
	f.calls.add("publish")
	f.published = append(f.published, e)
	return nil
}

// countingStore wraps the memory store and counts SetStatus calls.
type countingStore struct {
	Store
	setStatus int
}

func (s *countingStore) SetStatus(ctx context.Context, id string, st Status) error {
	s.setStatus++
	return s.Store.SetStatus(ctx, id, st)
}

type fixture struct {
	store *countingStore
	cart  *fakeCart
	pub   *fakePublisher
	calls *calls
	svc   *Service
}

func newFixture() *fixture {
	c := &calls{}
	f := &fixture{
		store: &countingStore{Store: NewMemoryStore()},
		cart: &fakeCart{calls: c, items: map[string][]cartItem{
			"sub-1": {{ProductID: "p1", Quantity: 2}, {ProductID: "p2", Quantity: 1}},
		}},
		pub:   &fakePublisher{calls: c},
		calls: c,
	}
	products := &fakeProducts{products: map[string]product{
		"p1": {ID: "p1", Name: "Mug", PriceCents: 15000, Currency: "VND"},
		"p2": {ID: "p2", Name: "Tee", PriceCents: 25000, Currency: "VND"},
	}}
	f.svc = NewService(f.store, f.cart, products, f.pub, slog.New(slog.NewJSONHandler(io.Discard, nil)))
	return f
}

func do(h http.Handler, method, path, sub, email string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, nil)
	if sub != "" {
		r.Header.Set("X-Customer-Sub", sub)
		r.Header.Set("X-Customer-Email", email)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	return rec
}

func (f *fixture) routes() http.Handler {
	return Routes(f.svc, slog.New(slog.NewJSONHandler(io.Discard, nil)))
}

func TestCheckout_CreatesPendingOrderPublishesAndClearsCart(t *testing.T) {
	f := newFixture()
	rec := do(f.routes(), "POST", "/api/orders", "sub-1", "a@example.com")

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (body %s)", rec.Code, rec.Body)
	}
	var got Order
	if err := json.NewDecoder(rec.Body).Decode(&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !strings.HasPrefix(got.ID, "ord-") || len(got.ID) != len("ord-")+8 {
		t.Errorf("id = %q, want ord-<8 hex>", got.ID)
	}
	if got.Status != PendingPayment || got.TotalCents != 2*15000+25000 || got.Currency != "VND" || got.CustomerSub != "sub-1" {
		t.Errorf("order = %+v", got)
	}
	if len(got.Items) != 2 || got.Items[0] != (Item{ProductID: "p1", Name: "Mug", UnitPriceCents: 15000, Quantity: 2}) {
		t.Errorf("items = %+v", got.Items)
	}

	stored, err := f.store.Get(context.Background(), got.ID, "sub-1")
	if err != nil || stored.Status != PendingPayment {
		t.Errorf("stored = %+v, err %v", stored, err)
	}
	if len(f.pub.published) != 1 {
		t.Fatalf("published %d events, want 1", len(f.pub.published))
	}
	e := f.pub.published[0]
	if e.EventType != events.OrderCreated || e.OrderID != got.ID || e.CustomerSub != "sub-1" || e.Email != "a@example.com" || e.TotalCents != got.TotalCents {
		t.Errorf("event = %+v", e)
	}
	if strings.Join(f.calls.log, ",") != "publish,clear" {
		t.Errorf("side effects = %v, want publish then clear", f.calls.log)
	}
	if len(f.cart.cleared) != 1 || f.cart.cleared[0] != "sub-1" {
		t.Errorf("cleared = %v", f.cart.cleared)
	}
}

func TestCheckout_EmptyCart(t *testing.T) {
	f := newFixture()
	rec := do(f.routes(), "POST", "/api/orders", "sub-empty", "b@example.com")

	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"cart is empty"}` {
		t.Errorf("body = %s", got)
	}
	if len(f.pub.published) != 0 {
		t.Errorf("published %v, want nothing", f.pub.published)
	}
	if list, _ := f.store.List(context.Background(), "sub-empty"); len(list) != 0 {
		t.Errorf("orders = %v, want none", list)
	}
}

func TestCheckout_UnknownProduct(t *testing.T) {
	f := newFixture()
	f.cart.items["sub-1"] = append(f.cart.items["sub-1"], cartItem{ProductID: "p9", Quantity: 1})
	rec := do(f.routes(), "POST", "/api/orders", "sub-1", "a@example.com")

	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"unknown product p9"}` {
		t.Errorf("body = %s", got)
	}
	if len(f.pub.published) != 0 || len(f.cart.cleared) != 0 {
		t.Errorf("published %v, cleared %v; want neither", f.pub.published, f.cart.cleared)
	}
	if list, _ := f.store.List(context.Background(), "sub-1"); len(list) != 0 {
		t.Errorf("orders = %v, want none", list)
	}
}

func TestCheckout_NoEmailStillCreatesOrder(t *testing.T) {
	f := newFixture()
	o, err := f.svc.Checkout(context.Background(), httpx.Identity{Sub: "sub-1"})
	if err != nil {
		t.Fatalf("Checkout: %v", err)
	}
	if o.Status != PendingPayment {
		t.Errorf("status = %s", o.Status)
	}
	if len(f.pub.published) != 1 || f.pub.published[0].Email != "" {
		t.Errorf("published = %+v, want one event with empty email", f.pub.published)
	}
}

func TestCheckout_CartClearFailureKeepsOrder(t *testing.T) {
	f := newFixture()
	f.cart.clearErr = errors.New("cart down")
	o, err := f.svc.Checkout(context.Background(), httpx.Identity{Sub: "sub-1", Email: "a@example.com"})
	if err != nil {
		t.Fatalf("Checkout: %v, want the order to stand", err)
	}
	if _, err := f.store.Get(context.Background(), o.ID, "sub-1"); err != nil {
		t.Errorf("order not stored: %v", err)
	}
}

func TestHandleEvent_PaymentSucceededSetsPaid(t *testing.T) {
	f := newFixture()
	ctx := context.Background()
	o, err := f.svc.Checkout(ctx, httpx.Identity{Sub: "sub-1"})
	if err != nil {
		t.Fatalf("Checkout: %v", err)
	}

	if err := f.svc.HandleEvent(ctx, events.New(events.PaymentSucceeded, o.ID, "sub-1", "", o.TotalCents)); err != nil {
		t.Fatalf("HandleEvent: %v", err)
	}
	got, _ := f.store.Get(ctx, o.ID, "sub-1")
	if got.Status != Paid {
		t.Errorf("status = %s, want PAID", got.Status)
	}

	o2, _ := f.svc.Checkout(ctx, httpx.Identity{Sub: "sub-1"})
	if err := f.svc.HandleEvent(ctx, events.New(events.PaymentFailed, o2.ID, "sub-1", "", o2.TotalCents)); err != nil {
		t.Fatalf("HandleEvent: %v", err)
	}
	if got, _ := f.store.Get(ctx, o2.ID, "sub-1"); got.Status != PaymentFailed {
		t.Errorf("status = %s, want PAYMENT_FAILED", got.Status)
	}
}

func TestHandleEvent_DuplicateIgnored(t *testing.T) {
	f := newFixture()
	ctx := context.Background()
	o, _ := f.svc.Checkout(ctx, httpx.Identity{Sub: "sub-1"})
	e := events.New(events.PaymentSucceeded, o.ID, "sub-1", "", o.TotalCents)

	for i := range 2 {
		if err := f.svc.HandleEvent(ctx, e); err != nil {
			t.Fatalf("HandleEvent #%d: %v", i+1, err)
		}
	}
	if f.store.setStatus != 1 {
		t.Errorf("SetStatus called %d times, want 1", f.store.setStatus)
	}
}

func TestGetOrder_OtherCustomer404(t *testing.T) {
	f := newFixture()
	h := f.routes()
	o, _ := f.svc.Checkout(context.Background(), httpx.Identity{Sub: "sub-1"})

	if rec := do(h, "GET", "/api/orders/"+o.ID, "sub-2", ""); rec.Code != http.StatusNotFound {
		t.Errorf("other customer: status = %d, want 404", rec.Code)
	}
	if rec := do(h, "GET", "/api/orders/"+o.ID, "sub-1", ""); rec.Code != http.StatusOK {
		t.Errorf("owner: status = %d, want 200", rec.Code)
	}
	rec := do(h, "GET", "/api/orders", "sub-2", "")
	if got := strings.TrimSpace(rec.Body.String()); rec.Code != http.StatusOK || got != "[]" {
		t.Errorf("other customer's list: %d %s, want 200 []", rec.Code, got)
	}
	if rec := do(h, "GET", "/api/orders", "", ""); rec.Code != http.StatusUnauthorized {
		t.Errorf("no identity: status = %d, want 401", rec.Code)
	}
	if rec := do(h, "GET", "/health", "", ""); rec.Code != http.StatusOK {
		t.Errorf("health: status = %d", rec.Code)
	}
}

func TestHTTPClients_SendIdentityAndOriginHeaders(t *testing.T) {
	var seen []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = append(seen, r.Method+" "+r.URL.Path+"?"+r.URL.Query().Get("ids")+" sub="+r.Header.Get("X-Customer-Sub")+" origin="+r.Header.Get("X-Origin-Verify"))
		switch {
		case r.Method == "GET" && r.URL.Path == "/api/cart":
			io.WriteString(w, `{"customer_sub":"sub-1","items":[{"product_id":"p1","quantity":2}],"updated_at":"2026-11-05T00:00:00Z"}`)
		case r.Method == "DELETE" && r.URL.Path == "/api/cart":
			w.WriteHeader(http.StatusNoContent)
		case r.Method == "GET" && r.URL.Path == "/api/products":
			io.WriteString(w, `[{"id":"p1","name":"Mug","description":"","price_cents":15000,"currency":"VND","category":"home","image_url":""}]`)
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	cartC, productC := NewHTTPClients(srv.URL+"/", "secret")
	ctx := context.Background()
	items, err := cartC.Get(ctx, "sub-1")
	if err != nil || len(items) != 1 || items[0] != (cartItem{ProductID: "p1", Quantity: 2}) {
		t.Errorf("cart Get = %+v, %v", items, err)
	}
	if err := cartC.Clear(ctx, "sub-1"); err != nil {
		t.Errorf("cart Clear: %v", err)
	}
	ps, err := productC.ByIDs(ctx, []string{"p1", "p2"})
	if err != nil || len(ps) != 1 || ps["p1"].PriceCents != 15000 || ps["p1"].Name != "Mug" {
		t.Errorf("ByIDs = %+v, %v", ps, err)
	}
	want := []string{
		"GET /api/cart? sub=sub-1 origin=secret",
		"DELETE /api/cart? sub=sub-1 origin=secret",
		"GET /api/products?p1,p2 sub= origin=secret",
	}
	if strings.Join(seen, "\n") != strings.Join(want, "\n") {
		t.Errorf("requests:\n%s\nwant:\n%s", strings.Join(seen, "\n"), strings.Join(want, "\n"))
	}
}

func TestHandleEvent_OnlyPendingOrdersTransition(t *testing.T) {
	f := newFixture()
	ctx := context.Background()
	o, _ := f.svc.Checkout(ctx, httpx.Identity{Sub: "sub-1"})

	if err := f.svc.HandleEvent(ctx, events.New(events.PaymentSucceeded, o.ID, "sub-1", "", o.TotalCents)); err != nil {
		t.Fatalf("HandleEvent succeeded: %v", err)
	}
	// A late, conflicting outcome (a different event id) must not move a PAID order, and is acked.
	if err := f.svc.HandleEvent(ctx, events.New(events.PaymentFailed, o.ID, "sub-1", "", o.TotalCents)); err != nil {
		t.Fatalf("HandleEvent failed-after-paid: %v, want nil (ack)", err)
	}
	if got, _ := f.store.Get(ctx, o.ID, "sub-1"); got.Status != Paid {
		t.Errorf("status = %s, want PAID", got.Status)
	}
	if err := f.store.SetStatus(ctx, o.ID, PaymentFailed); !errors.Is(err, ErrNotPending) {
		t.Errorf("memory SetStatus on a PAID order = %v, want ErrNotPending", err)
	}
	if err := f.store.SetStatus(ctx, "ord-missing", Paid); !errors.Is(err, ErrNotFound) {
		t.Errorf("SetStatus on a missing order = %v, want ErrNotFound", err)
	}
}
