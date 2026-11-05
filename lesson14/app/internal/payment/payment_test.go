package payment

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
)

type fakePublisher struct{ published []events.Event }

func (f *fakePublisher) Publish(_ context.Context, e events.Event) error {
	f.published = append(f.published, e)
	return nil
}

// countingStore wraps the memory store and counts rows created.
type countingStore struct {
	Store
	created int
}

func (s *countingStore) Create(ctx context.Context, p Payment) error {
	s.created++
	return s.Store.Create(ctx, p)
}

func discard() *slog.Logger { return slog.New(slog.NewJSONHandler(io.Discard, nil)) }

func newService() (*Service, *countingStore, *fakePublisher) {
	store := &countingStore{Store: NewMemoryStore()}
	pub := &fakePublisher{}
	return NewService(store, pub, discard()), store, pub
}

func TestDecide_Rule(t *testing.T) {
	cases := []struct {
		total              int64
		wantStatus, reason string
	}{
		{1999, Failed, "card declined (demo rule: totals ending in 99)"},
		{2000, Succeeded, ""},
		{99, Failed, "card declined (demo rule: totals ending in 99)"},
		{55000, Succeeded, ""},
	}
	for _, c := range cases {
		status, reason := Decide(c.total)
		if status != c.wantStatus || reason != c.reason {
			t.Errorf("Decide(%d) = %q, %q; want %q, %q", c.total, status, reason, c.wantStatus, c.reason)
		}
	}
}

func TestHandle_CreatesPaymentAndPublishesOutcome(t *testing.T) {
	cases := []struct {
		name      string
		total     int64
		wantType  string
		wantState string
	}{
		{"succeeds", 55000, events.PaymentSucceeded, Succeeded},
		{"fails on 99", 54999, events.PaymentFailed, Failed},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			svc, store, pub := newService()
			ctx := context.Background()
			in := events.New(events.OrderCreated, "ord-1", "sub-1", "a@example.com", c.total)

			if err := svc.HandleEvent(ctx, in); err != nil {
				t.Fatalf("HandleEvent: %v", err)
			}
			p, err := store.ByOrder(ctx, "ord-1", "sub-1")
			if err != nil {
				t.Fatalf("ByOrder: %v", err)
			}
			if !strings.HasPrefix(p.ID, "pay-") || len(p.ID) != len("pay-")+8 {
				t.Errorf("id = %q, want pay-<8 hex>", p.ID)
			}
			if p.Status != c.wantState || p.AmountCents != c.total || p.CustomerSub != "sub-1" || p.CreatedAt.IsZero() {
				t.Errorf("payment = %+v", p)
			}
			if len(pub.published) != 1 {
				t.Fatalf("published %d events, want 1", len(pub.published))
			}
			out := pub.published[0]
			if out.EventType != c.wantType || out.OrderID != "ord-1" || out.CustomerSub != "sub-1" ||
				out.Email != "a@example.com" || out.TotalCents != c.total || out.Reason != p.Reason || out.EventID == in.EventID {
				t.Errorf("outcome = %+v (payment %+v)", out, p)
			}
		})
	}
}

func TestHandle_DuplicateEventIsIgnored(t *testing.T) {
	svc, store, pub := newService()
	ctx := context.Background()
	in := events.New(events.OrderCreated, "ord-1", "sub-1", "", 2000)

	for i := range 2 {
		if err := svc.HandleEvent(ctx, in); err != nil {
			t.Fatalf("HandleEvent #%d: %v", i+1, err)
		}
	}
	if store.created != 1 {
		t.Errorf("Create called %d times, want 1", store.created)
	}
	if len(pub.published) != 1 {
		t.Errorf("published %d events, want 1", len(pub.published))
	}
}

func TestHandle_IgnoresOtherEventTypes(t *testing.T) {
	svc, store, pub := newService()
	if err := svc.HandleEvent(context.Background(), events.New(events.PaymentSucceeded, "ord-1", "sub-1", "", 2000)); err != nil {
		t.Fatalf("HandleEvent: %v", err)
	}
	if store.created != 0 || len(pub.published) != 0 {
		t.Errorf("created %d, published %d; want neither", store.created, len(pub.published))
	}
}

func do(h http.Handler, path, sub string) *httptest.ResponseRecorder {
	r := httptest.NewRequest("GET", path, nil)
	if sub != "" {
		r.Header.Set("X-Customer-Sub", sub)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	return rec
}

func TestGetPayment_OtherCustomer404(t *testing.T) {
	svc, _, _ := newService()
	if err := svc.HandleEvent(context.Background(), events.New(events.OrderCreated, "ord-1", "sub-1", "", 1999)); err != nil {
		t.Fatalf("HandleEvent: %v", err)
	}
	h := Routes(svc, discard())

	if rec := do(h, "/api/payments/ord-1", "sub-2"); rec.Code != http.StatusNotFound {
		t.Errorf("other customer: status = %d, want 404", rec.Code)
	}
	if rec := do(h, "/api/payments/ord-404", "sub-1"); rec.Code != http.StatusNotFound {
		t.Errorf("no payment: status = %d, want 404", rec.Code)
	}
	rec := do(h, "/api/payments/ord-1", "sub-1")
	if rec.Code != http.StatusOK {
		t.Fatalf("owner: status = %d, want 200", rec.Code)
	}
	var body map[string]any
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	for _, k := range []string{"id", "order_id", "customer_sub", "amount_cents", "status", "reason", "created_at"} {
		if _, ok := body[k]; !ok {
			t.Errorf("payment JSON lacks %q: %v", k, body)
		}
	}
	if body["status"] != Failed {
		t.Errorf("status = %v, want FAILED", body["status"])
	}
	if rec := do(h, "/api/payments/ord-1", ""); rec.Code != http.StatusUnauthorized {
		t.Errorf("no identity: status = %d, want 401", rec.Code)
	}
	if rec := do(h, "/health", ""); rec.Code != http.StatusOK {
		t.Errorf("health: status = %d", rec.Code)
	}
}
