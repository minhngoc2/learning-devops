package product

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DDL creates the service's table; the name is unqualified because search_path is the products schema.
var DDL = []string{
	`CREATE TABLE IF NOT EXISTS products (
		id          text PRIMARY KEY,
		name        text NOT NULL,
		description text NOT NULL DEFAULT '',
		price_cents bigint NOT NULL CHECK (price_cents > 0),
		currency    text NOT NULL,
		category    text NOT NULL DEFAULT '',
		image_key   text NOT NULL DEFAULT '',
		created_at  timestamptz NOT NULL DEFAULT now()
	)`,
	`CREATE INDEX IF NOT EXISTS products_category_idx ON products (category)`,
}

type pgStore struct{ pool *pgxpool.Pool }

// NewPGStore stores products in PostgreSQL; run DDL first.
func NewPGStore(pool *pgxpool.Pool) Store { return &pgStore{pool: pool} }

const selectProducts = `SELECT id, name, description, price_cents, currency, category, image_key, created_at FROM products`

func (s *pgStore) List(ctx context.Context) ([]Product, error) {
	return s.query(ctx, selectProducts+` ORDER BY id`)
}

func (s *pgStore) ByIDs(ctx context.Context, ids []string) ([]Product, error) {
	return s.query(ctx, selectProducts+` WHERE id = ANY($1) ORDER BY id`, ids)
}

func (s *pgStore) Get(ctx context.Context, id string) (Product, error) {
	list, err := s.query(ctx, selectProducts+` WHERE id = $1`, id)
	if err != nil {
		return Product{}, err
	}
	if len(list) == 0 {
		return Product{}, ErrNotFound
	}
	return list[0], nil
}

func (s *pgStore) Create(ctx context.Context, p Product) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO products (id, name, description, price_cents, currency, category, image_key, created_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		p.ID, p.Name, p.Description, p.PriceCents, p.Currency, p.Category, p.ImageKey, p.CreatedAt)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" { // unique_violation
		return ErrDuplicate
	}
	if err != nil {
		return fmt.Errorf("insert product: %w", err)
	}
	return nil
}

func (s *pgStore) query(ctx context.Context, sql string, args ...any) ([]Product, error) {
	rows, err := s.pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, fmt.Errorf("select products: %w", err)
	}
	list, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (Product, error) {
		var p Product
		err := row.Scan(&p.ID, &p.Name, &p.Description, &p.PriceCents, &p.Currency, &p.Category, &p.ImageKey, &p.CreatedAt)
		return p, err
	})
	if err != nil {
		return nil, fmt.Errorf("scan products: %w", err)
	}
	if list == nil {
		list = []Product{}
	}
	return list, nil
}
