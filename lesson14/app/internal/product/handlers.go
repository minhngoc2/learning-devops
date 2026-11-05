package product

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
)

// seedID is the shape of a caller-chosen id (the seed uses stable ids such as p-0001).
var seedID = regexp.MustCompile(`^p-[a-z0-9-]{1,32}$`)

// view is the API shape: the stored product plus image_url.
type view struct {
	Product
	ImageURL string `json:"image_url"`
}

// Routes mounts GET /api/products (?ids=a,b filters by id, unknown ids are absent; ?category= filters by
// category), GET /api/products/{id}, POST /api/products (needs an identity; 201) and GET /health.
// publicBaseURL is where /images/* is served (CloudFront on AWS).
func Routes(s Store, publicBaseURL string, log *slog.Logger) http.Handler {
	h := handlers{store: s, base: strings.TrimRight(publicBaseURL, "/"), log: log}
	mux := http.NewServeMux()
	mux.Handle("GET /health", httpx.Health())
	mux.HandleFunc("GET /api/products", h.list)
	mux.HandleFunc("GET /api/products/{id}", h.get)
	mux.Handle("POST /api/products", httpx.RequireIdentity(http.HandlerFunc(h.create)))
	return httpx.Logging(log, mux)
}

type handlers struct {
	store Store
	base  string
	log   *slog.Logger
}

func (h handlers) view(p Product) view {
	v := view{Product: p}
	if p.ImageKey != "" {
		v.ImageURL = h.base + "/images/" + p.ImageKey
	}
	return v
}

func (h handlers) list(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	var (
		list []Product
		err  error
	)
	if q.Has("ids") {
		ids := slices.DeleteFunc(strings.Split(q.Get("ids"), ","), func(s string) bool { return s == "" })
		list, err = h.store.ByIDs(r.Context(), ids)
	} else {
		list, err = h.store.List(r.Context())
	}
	if err != nil {
		h.internal(w, "list products", err)
		return
	}
	category := q.Get("category")
	out := make([]view, 0, len(list))
	for _, p := range list {
		if category == "" || p.Category == category {
			out = append(out, h.view(p))
		}
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h handlers) get(w http.ResponseWriter, r *http.Request) {
	p, err := h.store.Get(r.Context(), r.PathValue("id"))
	switch {
	case err == nil:
		httpx.WriteJSON(w, http.StatusOK, h.view(p))
	case errors.Is(err, ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "product not found")
	default:
		h.internal(w, "get product", err)
	}
}

type createRequest struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	PriceCents  int64  `json:"price_cents"`
	Currency    string `json:"currency"`
	Category    string `json:"category"`
	ImageKey    string `json:"image_key"`
}

func (h handlers) create(w http.ResponseWriter, r *http.Request) {
	var req createRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	switch {
	case strings.TrimSpace(req.Name) == "":
		httpx.WriteError(w, http.StatusBadRequest, "name is required")
		return
	case req.PriceCents <= 0:
		httpx.WriteError(w, http.StatusBadRequest, "price_cents must be positive")
		return
	case strings.TrimSpace(req.Currency) == "":
		httpx.WriteError(w, http.StatusBadRequest, "currency is required")
		return
	case req.ID != "" && !seedID.MatchString(req.ID):
		httpx.WriteError(w, http.StatusBadRequest, "id must match ^p-[a-z0-9-]{1,32}$")
		return
	}
	if req.ID == "" {
		req.ID = newID()
	}
	p := Product{
		ID: req.ID, Name: req.Name, Description: req.Description, PriceCents: req.PriceCents,
		Currency: req.Currency, Category: req.Category, ImageKey: req.ImageKey, CreatedAt: time.Now().UTC(),
	}
	err := h.store.Create(r.Context(), p)
	switch {
	case err == nil:
		httpx.WriteJSON(w, http.StatusCreated, h.view(p))
	case errors.Is(err, ErrDuplicate):
		httpx.WriteError(w, http.StatusConflict, "product id already exists")
	default:
		h.internal(w, "create product", err)
	}
}

func (h handlers) internal(w http.ResponseWriter, msg string, err error) {
	h.log.Error(msg, "err", err)
	httpx.WriteError(w, http.StatusInternalServerError, "internal error")
}

// newID returns "p-" + 8 random hex characters.
func newID() string {
	b := make([]byte, 4)
	_, _ = rand.Read(b) // crypto/rand.Read never fails on supported platforms
	return "p-" + hex.EncodeToString(b)
}
