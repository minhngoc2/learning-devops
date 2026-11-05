// Package pg opens the PostgreSQL pool for services that own a schema on the shared RDS instance.
package pg

import (
	"context"
	"fmt"
	"net"
	"net/url"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/minhngoc2/learning-devops/lesson14/internal/config"
)

// Connect builds the DSN from DB_HOST, DB_PORT (5432), DB_NAME, DB_USER, DB_PASSWORD and DB_SSLMODE
// (require; compose sets disable), sets search_path to DB_SCHEMA so unqualified table names land in the
// service's own schema, and pings once so a bad config fails at startup.
func Connect(ctx context.Context) (*pgxpool.Pool, error) {
	u := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(config.Get("DB_USER", ""), config.Get("DB_PASSWORD", "")),
		Host:     net.JoinHostPort(config.Get("DB_HOST", "localhost"), config.Get("DB_PORT", "5432")),
		Path:     config.Get("DB_NAME", ""),
		RawQuery: url.Values{"sslmode": {config.Get("DB_SSLMODE", "require")}}.Encode(),
	}
	cfg, err := pgxpool.ParseConfig(u.String())
	if err != nil {
		return nil, fmt.Errorf("pg: parse config: %w", err)
	}
	if schema := config.Get("DB_SCHEMA", ""); schema != "" {
		cfg.ConnConfig.RuntimeParams["search_path"] = schema
	}

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("pg: open pool: %w", err)
	}
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("pg: ping %s: %w", u.Host, err)
	}
	return pool, nil
}
