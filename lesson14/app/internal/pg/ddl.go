package pg

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ProcessedEventsDDL creates the event-id dedupe table that every event-consuming service keeps in its own
// schema; MarkProcessed writes to it.
const ProcessedEventsDDL = `CREATE TABLE IF NOT EXISTS processed_events (
		event_id     text PRIMARY KEY,
		processed_at timestamptz NOT NULL DEFAULT now()
	)`

// Exec runs idempotent DDL statements (CREATE TABLE IF NOT EXISTS ...) in order at startup; the schema is
// small enough that a migration tool would be more machinery than it saves.
func Exec(ctx context.Context, pool *pgxpool.Pool, ddl ...string) error {
	for i, stmt := range ddl {
		if _, err := pool.Exec(ctx, stmt); err != nil {
			return fmt.Errorf("pg: ddl statement %d: %w", i+1, err)
		}
	}
	return nil
}

// MarkProcessed records eventID in processed_events and reports whether this is its first delivery.
func MarkProcessed(ctx context.Context, pool *pgxpool.Pool, eventID string) (first bool, err error) {
	var id string
	err = pool.QueryRow(ctx,
		`INSERT INTO processed_events (event_id) VALUES ($1) ON CONFLICT (event_id) DO NOTHING RETURNING event_id`,
		eventID).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("mark event processed: %w", err)
	}
	return true, nil
}
