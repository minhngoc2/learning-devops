package httpx

import (
	"bytes"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRequireIdentity_MissingHeader401(t *testing.T) {
	called := false
	h := RequireIdentity(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { called = true }))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/api/cart", nil))

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
	if called {
		t.Error("next handler ran without identity")
	}
	var body map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil || body["error"] != "unauthenticated" {
		t.Errorf("body = %v (err %v), want {\"error\":\"unauthenticated\"}", body, err)
	}
}

func TestIdentityFrom_ReadsBothHeaders(t *testing.T) {
	r := httptest.NewRequest("GET", "/", nil)
	r.Header.Set("X-Customer-Sub", "sub-123")
	r.Header.Set("X-Customer-Email", "a@example.com")

	id, ok := IdentityFrom(r)
	if !ok {
		t.Fatal("ok = false, want true")
	}
	if id != (Identity{Sub: "sub-123", Email: "a@example.com"}) {
		t.Errorf("identity = %+v", id)
	}
}

func TestDecodeJSON_RejectsOversizedBody(t *testing.T) {
	const limit = 1 << 20
	prefix, suffix := `{"title":"`, `"}`
	body := prefix + strings.Repeat("x", limit+1-len(prefix)-len(suffix)) + suffix
	if len(body) != limit+1 {
		t.Fatalf("test body is %d bytes, want %d", len(body), limit+1)
	}

	var v struct{ Title string }
	if err := DecodeJSON(httptest.NewRequest("POST", "/", strings.NewReader(body)), &v); err == nil {
		t.Error("DecodeJSON accepted a 1 MiB + 1 body")
	}
}

func TestHealth_OK(t *testing.T) {
	rec := httptest.NewRecorder()
	Health().ServeHTTP(rec, httptest.NewRequest("GET", "/health", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"status":"ok"}` {
		t.Errorf("body = %s", got)
	}
}

func TestHealthcheckFlag_ScansArgsWithoutFlagParse(t *testing.T) {
	cases := map[string]struct {
		args []string
		want bool
	}{
		"none":             {nil, false},
		"single dash":      {[]string{"-healthcheck"}, true},
		"double dash":      {[]string{"--healthcheck"}, true},
		"other flags only": {[]string{"-port=1", "healthcheck"}, false},
	}
	for name, c := range cases {
		if got := HasHealthcheckArg(c.args); got != c.want {
			t.Errorf("%s: HasHealthcheckArg(%v) = %v, want %v", name, c.args, got, c.want)
		}
	}
	// The test binary's own -test.* args carry no -healthcheck, so this must return without probing.
	if HealthcheckFlag("1") {
		t.Error("HealthcheckFlag = true without -healthcheck")
	}
}

func TestInternal_LogsErrorAndHidesIt(t *testing.T) {
	var logs bytes.Buffer
	rec := httptest.NewRecorder()
	Internal(rec, slog.New(slog.NewJSONHandler(&logs, nil)), "get cart", errors.New("dynamodb: boom"))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"internal error"}` {
		t.Errorf("body = %s", got)
	}
	var line map[string]any
	if err := json.Unmarshal(logs.Bytes(), &line); err != nil || line["level"] != "ERROR" || line["msg"] != "get cart" || line["err"] != "dynamodb: boom" {
		t.Errorf("log = %s (err %v)", logs.String(), err)
	}
}
