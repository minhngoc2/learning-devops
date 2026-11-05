package pg

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

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
