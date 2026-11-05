package user

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DDL creates the service's table; the name is unqualified because search_path is the users schema.
var DDL = []string{
	`CREATE TABLE IF NOT EXISTS customers (
		sub          text PRIMARY KEY,
		email        text NOT NULL,
		display_name text NOT NULL,
		created_at   timestamptz NOT NULL DEFAULT now()
	)`,
}

type pgStore struct{ pool *pgxpool.Pool }

// NewPGStore stores Customers in PostgreSQL; run DDL first.
func NewPGStore(pool *pgxpool.Pool) Store { return &pgStore{pool: pool} }

func (s *pgStore) Create(ctx context.Context, c Customer) (bool, error) {
	tag, err := s.pool.Exec(ctx,
		`INSERT INTO customers (sub, email, display_name, created_at) VALUES ($1, $2, $3, $4)
		 ON CONFLICT (sub) DO NOTHING`,
		c.Sub, c.Email, c.DisplayName, c.CreatedAt)
	if err != nil {
		return false, fmt.Errorf("insert customer: %w", err)
	}
	return tag.RowsAffected() == 1, nil
}

func (s *pgStore) Get(ctx context.Context, sub string) (Customer, error) {
	var c Customer
	err := s.pool.QueryRow(ctx, `SELECT sub, email, display_name, created_at FROM customers WHERE sub = $1`, sub).
		Scan(&c.Sub, &c.Email, &c.DisplayName, &c.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Customer{}, ErrNotFound
	}
	if err != nil {
		return Customer{}, fmt.Errorf("select customer: %w", err)
	}
	return c, nil
}
