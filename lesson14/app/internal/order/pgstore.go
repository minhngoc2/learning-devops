package order

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/minhngoc2/learning-devops/lesson14/internal/pg"
)

// DDL creates the service's tables; table names are unqualified because search_path is the orders schema.
var DDL = []string{
	`CREATE TABLE IF NOT EXISTS orders (
		id           text PRIMARY KEY,
		customer_sub text NOT NULL,
		status       text NOT NULL CHECK (status IN ('PENDING_PAYMENT', 'PAID', 'PAYMENT_FAILED')),
		total_cents  bigint NOT NULL CHECK (total_cents >= 0),
		currency     text NOT NULL,
		created_at   timestamptz NOT NULL DEFAULT now(),
		updated_at   timestamptz NOT NULL DEFAULT now()
	)`,
	`CREATE INDEX IF NOT EXISTS orders_customer_sub_created_at_idx ON orders (customer_sub, created_at DESC)`,
	`CREATE TABLE IF NOT EXISTS order_items (
		order_id         text NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
		product_id       text NOT NULL,
		name             text NOT NULL,
		unit_price_cents bigint NOT NULL CHECK (unit_price_cents >= 0),
		quantity         integer NOT NULL CHECK (quantity > 0),
		PRIMARY KEY (order_id, product_id)
	)`,
	pg.ProcessedEventsDDL,
}

type pgStore struct{ pool *pgxpool.Pool }

// NewPGStore stores orders in PostgreSQL; run DDL first.
func NewPGStore(pool *pgxpool.Pool) Store { return &pgStore{pool: pool} }

// Create inserts the order and its lines in one transaction.
func (s *pgStore) Create(ctx context.Context, o Order) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx,
			`INSERT INTO orders (id, customer_sub, status, total_cents, currency, created_at, updated_at)
			 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			o.ID, o.CustomerSub, string(o.Status), o.TotalCents, o.Currency, o.CreatedAt, o.UpdatedAt); err != nil {
			return fmt.Errorf("insert order: %w", err)
		}
		for _, it := range o.Items {
			if _, err := tx.Exec(ctx,
				`INSERT INTO order_items (order_id, product_id, name, unit_price_cents, quantity) VALUES ($1, $2, $3, $4, $5)`,
				o.ID, it.ProductID, it.Name, it.UnitPriceCents, it.Quantity); err != nil {
				return fmt.Errorf("insert order item: %w", err)
			}
		}
		return nil
	})
}

const selectOrders = `SELECT id, customer_sub, status, total_cents, currency, created_at, updated_at FROM orders`

func (s *pgStore) Get(ctx context.Context, id, sub string) (Order, error) {
	orders, err := s.query(ctx, selectOrders+` WHERE id = $1 AND customer_sub = $2`, id, sub)
	if err != nil {
		return Order{}, err
	}
	if len(orders) == 0 {
		return Order{}, ErrNotFound
	}
	return orders[0], nil
}

func (s *pgStore) List(ctx context.Context, sub string) ([]Order, error) {
	return s.query(ctx, selectOrders+` WHERE customer_sub = $1 ORDER BY created_at DESC, id`, sub)
}

// query reads the matching orders, then all their lines in one more query.
func (s *pgStore) query(ctx context.Context, sql string, args ...any) ([]Order, error) {
	rows, err := s.pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, fmt.Errorf("select orders: %w", err)
	}
	orders, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (Order, error) {
		var o Order
		err := row.Scan(&o.ID, &o.CustomerSub, &o.Status, &o.TotalCents, &o.Currency, &o.CreatedAt, &o.UpdatedAt)
		o.Items = []Item{}
		return o, err
	})
	if err != nil {
		return nil, fmt.Errorf("scan orders: %w", err)
	}
	if len(orders) == 0 {
		return []Order{}, nil
	}

	ids := make([]string, len(orders))
	byID := make(map[string]*Order, len(orders))
	for i := range orders {
		ids[i] = orders[i].ID
		byID[orders[i].ID] = &orders[i]
	}
	rows, err = s.pool.Query(ctx,
		`SELECT order_id, product_id, name, unit_price_cents, quantity FROM order_items
		 WHERE order_id = ANY($1) ORDER BY order_id, product_id`, ids)
	if err != nil {
		return nil, fmt.Errorf("select order items: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var orderID string
		var it Item
		if err := rows.Scan(&orderID, &it.ProductID, &it.Name, &it.UnitPriceCents, &it.Quantity); err != nil {
			return nil, fmt.Errorf("scan order item: %w", err)
		}
		byID[orderID].Items = append(byID[orderID].Items, it)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read order items: %w", err)
	}
	return orders, nil
}

func (s *pgStore) SetStatus(ctx context.Context, id string, st Status) error {
	tag, err := s.pool.Exec(ctx, `UPDATE orders SET status = $2, updated_at = now() WHERE id = $1`, id, string(st))
	if err != nil {
		return fmt.Errorf("update order status: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *pgStore) MarkProcessed(ctx context.Context, eventID string) (bool, error) {
	return pg.MarkProcessed(ctx, s.pool, eventID)
}
