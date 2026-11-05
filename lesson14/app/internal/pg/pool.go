// Package pg opens the PostgreSQL pool for services that own a schema on the shared RDS instance.
package pg

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/url"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/minhngoc2/learning-devops/lesson14/internal/config"
)

// ConfigFromEnv builds the pool config from DB_HOST, DB_PORT (5432), DB_NAME, DB_USER, DB_PASSWORD and
// DB_SSLMODE (require; compose sets disable), and sets search_path to DB_SCHEMA so unqualified table names
// land in the service's own schema. DB_SCHEMA is required: without it tables would land in public.
func ConfigFromEnv() (*pgxpool.Config, error) {
	schema := config.Get("DB_SCHEMA", "")
	if schema == "" {
		return nil, errors.New("pg: DB_SCHEMA is not set")
	}
	cfg, err := parse(config.Get("DB_USER", ""), config.Get("DB_PASSWORD", ""))
	if err != nil {
		return nil, err
	}
	cfg.ConnConfig.RuntimeParams["search_path"] = schema
	return cfg, nil
}

// AdminConfigFromEnv is ConfigFromEnv for db-init: the same host, port, database and sslmode, but logged
// in as user/password (the RDS master) and without a schema.
func AdminConfigFromEnv(user, password string) (*pgx.ConnConfig, error) {
	cfg, err := parse(user, password)
	if err != nil {
		return nil, err
	}
	return cfg.ConnConfig, nil
}

func parse(user, password string) (*pgxpool.Config, error) {
	u := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(user, password),
		Host:     net.JoinHostPort(config.Get("DB_HOST", "localhost"), config.Get("DB_PORT", "5432")),
		Path:     config.Get("DB_NAME", ""),
		RawQuery: url.Values{"sslmode": {config.Get("DB_SSLMODE", "require")}}.Encode(),
	}
	cfg, err := pgxpool.ParseConfig(u.String())
	if err != nil {
		return nil, fmt.Errorf("pg: parse config: %w", err)
	}
	return cfg, nil
}

// Connect opens a pool from ConfigFromEnv and pings once so a bad config fails at startup.
func Connect(ctx context.Context) (*pgxpool.Pool, error) {
	cfg, err := ConfigFromEnv()
	if err != nil {
		return nil, err
	}
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("pg: open pool: %w", err)
	}
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("pg: ping %s: %w", net.JoinHostPort(cfg.ConnConfig.Host, fmt.Sprint(cfg.ConnConfig.Port)), err)
	}
	return pool, nil
}
