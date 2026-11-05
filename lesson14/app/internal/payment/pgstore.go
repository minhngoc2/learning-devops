package payment

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/minhngoc2/learning-devops/lesson14/internal/pg"
)

// DDL creates the service's tables; table names are unqualified because search_path is the payments schema.
var DDL = []string{
	`CREATE TABLE IF NOT EXISTS payments (
		id           text PRIMARY KEY,
		order_id     text NOT NULL UNIQUE,
		customer_sub text NOT NULL,
		amount_cents bigint NOT NULL CHECK (amount_cents >= 0),
		status       text NOT NULL CHECK (status IN ('SUCCEEDED', 'FAILED')),
		reason       text NOT NULL DEFAULT '',
		created_at   timestamptz NOT NULL DEFAULT now()
	)`,
	pg.ProcessedEventsDDL,
}

type pgStore struct{ pool *pgxpool.Pool }

// NewPGStore stores payments in PostgreSQL; run DDL first.
func NewPGStore(pool *pgxpool.Pool) Store { return &pgStore{pool: pool} }

func (s *pgStore) Create(ctx context.Context, p Payment) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO payments (id, order_id, customer_sub, amount_cents, status, reason, created_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		p.ID, p.OrderID, p.CustomerSub, p.AmountCents, p.Status, p.Reason, p.CreatedAt)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "payments_order_id_key" {
		return ErrDuplicateOrder
	}
	if err != nil {
		return fmt.Errorf("insert payment: %w", err)
	}
	return nil
}

func (s *pgStore) ByOrder(ctx context.Context, orderID, sub string) (Payment, error) {
	var p Payment
	err := s.pool.QueryRow(ctx,
		`SELECT id, order_id, customer_sub, amount_cents, status, reason, created_at
		 FROM payments WHERE order_id = $1 AND customer_sub = $2`, orderID, sub).
		Scan(&p.ID, &p.OrderID, &p.CustomerSub, &p.AmountCents, &p.Status, &p.Reason, &p.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Payment{}, ErrNotFound
	}
	if err != nil {
		return Payment{}, fmt.Errorf("select payment: %w", err)
	}
	return p, nil
}

func (s *pgStore) MarkProcessed(ctx context.Context, eventID string) (bool, error) {
	return pg.MarkProcessed(ctx, s.pool, eventID)
}
