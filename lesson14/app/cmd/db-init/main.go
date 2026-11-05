// db-init: one-shot bootstrap run before the services (an ECS run-task on AWS, a compose job locally).
// It connects as the RDS master user and, in one transaction, creates each service's schema and svc_* role
// with the password from ROLE_PASSWORD_<SERVICE>. Safe to re-run; exits non-zero on any error.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/minhngoc2/learning-devops/lesson14/internal/config"
	"github.com/minhngoc2/learning-devops/lesson14/internal/dbinit"
	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
	"github.com/minhngoc2/learning-devops/lesson14/internal/pg"
)

func main() {
	// The shared image's HEALTHCHECK runs "/app -healthcheck"; db-init serves nothing, so answer healthy
	// instead of running the bootstrap a second time.
	if httpx.HasHealthcheckArg(os.Args[1:]) {
		return
	}
	log := httpx.NewLogger()
	slog.SetDefault(log)
	if err := run(log); err != nil {
		log.Error("db-init failed", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()

	roles := map[string]string{}
	for _, s := range dbinit.Services {
		roles[s.Key] = config.Get("ROLE_PASSWORD_"+strings.ToUpper(s.Key), "")
	}
	if err := dbinit.Validate(roles); err != nil {
		return err
	}
	admin, dbName := config.Get("DB_ADMIN_USER", ""), config.Get("DB_NAME", "")
	if admin == "" || dbName == "" {
		return errors.New("DB_ADMIN_USER and DB_NAME must be set")
	}

	cfg, err := pg.AdminConfigFromEnv(admin, config.Get("DB_ADMIN_PASSWORD", ""))
	if err != nil {
		return err
	}
	conn, err := pgx.ConnectConfig(ctx, cfg)
	if err != nil {
		return fmt.Errorf("connect %s as %s: %w", net.JoinHostPort(cfg.Host, strconv.Itoa(int(cfg.Port))), admin, err)
	}
	defer conn.Close(context.Background())

	stmts := dbinit.Statements(roles)
	perService := len(stmts) / len(dbinit.Services)
	err = pgx.BeginFunc(ctx, conn, func(tx pgx.Tx) error {
		// The password literals rely on backslashes being literal; do not trust the server default.
		if _, err := tx.Exec(ctx, "SET LOCAL standard_conforming_strings = on"); err != nil {
			return fmt.Errorf("set standard_conforming_strings: %w", err)
		}
		for i, stmt := range stmts {
			if _, err := tx.Exec(ctx, stmt); err != nil {
				// The statement may hold a password, so name it by position only.
				svc := dbinit.Services[i/perService]
				return fmt.Errorf("statement %d (schema %s): %w", i+1, svc.Schema, err)
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	for _, s := range dbinit.Services {
		log.Info("schema ready", "schema", s.Schema, "role", "svc_"+s.Key)
	}
	return nil
}
