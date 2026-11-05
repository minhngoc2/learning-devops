package order

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// cartItem is one line of GET /api/cart.
type cartItem struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

// product is one entry of GET /api/products?ids=…; only Name and PriceCents are used.
type product struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	PriceCents  int64  `json:"price_cents"`
	Currency    string `json:"currency"`
	Category    string `json:"category"`
	ImageURL    string `json:"image_url"`
}

// CartClient reads and clears a customer's Cart.
type CartClient interface {
	Get(ctx context.Context, sub string) ([]cartItem, error)
	Clear(ctx context.Context, sub string) error
}

// ProductClient looks products up by id; ids it does not know are absent from the map.
type ProductClient interface {
	ByIDs(ctx context.Context, ids []string) (map[string]product, error)
}

// NewHTTPClients calls Cart and Product Service through the internal ALB at albURL. Every request carries
// X-Origin-Verify (the listener rejects requests without it); cart requests also carry X-Customer-Sub.
func NewHTTPClients(albURL, originVerify string) (CartClient, ProductClient) {
	c := &albClient{
		baseURL:      strings.TrimRight(albURL, "/"),
		originVerify: originVerify,
		http:         &http.Client{Timeout: 5 * time.Second},
	}
	return cartClient{c}, productClient{c}
}

type albClient struct {
	baseURL      string
	originVerify string
	http         *http.Client
}

// do sends the request and decodes a 2xx JSON body into out (if non-nil); other statuses are errors.
func (c *albClient) do(ctx context.Context, method, path, sub string, out any) error {
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, nil)
	if err != nil {
		return err
	}
	if c.originVerify != "" {
		req.Header.Set("X-Origin-Verify", c.originVerify)
	}
	if sub != "" {
		req.Header.Set("X-Customer-Sub", sub)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<16))
		return fmt.Errorf("%s %s: status %d", method, path, resp.StatusCode)
	}
	if out == nil {
		return nil
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(out); err != nil {
		return fmt.Errorf("%s %s: decode: %w", method, path, err)
	}
	return nil
}

type cartClient struct{ c *albClient }

func (cc cartClient) Get(ctx context.Context, sub string) ([]cartItem, error) {
	var body struct {
		Items []cartItem `json:"items"`
	}
	if err := cc.c.do(ctx, http.MethodGet, "/api/cart", sub, &body); err != nil {
		return nil, err
	}
	return body.Items, nil
}

func (cc cartClient) Clear(ctx context.Context, sub string) error {
	return cc.c.do(ctx, http.MethodDelete, "/api/cart", sub, nil)
}

type productClient struct{ c *albClient }

func (pc productClient) ByIDs(ctx context.Context, ids []string) (map[string]product, error) {
	out := make(map[string]product, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	var list []product
	path := "/api/products?" + url.Values{"ids": {strings.Join(ids, ",")}}.Encode()
	if err := pc.c.do(ctx, http.MethodGet, path, "", &list); err != nil {
		return nil, err
	}
	for _, p := range list {
		out[p.ID] = p
	}
	return out, nil
}
