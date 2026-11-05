// Payment Service: charges OrderCreated events from its queue and serves GET /api/payments/{orderId}.
// Both loops run under one signal context; when either fails, the task exits so ECS replaces it.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"golang.org/x/sync/errgroup"

	"github.com/minhngoc2/learning-devops/lesson14/internal/config"
	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
	"github.com/minhngoc2/learning-devops/lesson14/internal/payment"
	"github.com/minhngoc2/learning-devops/lesson14/internal/pg"
)

func main() {
	port := config.Get("PORT", "8080")
	if httpx.HealthcheckFlag(port) {
		return
	}
	log := httpx.NewLogger()
	slog.SetDefault(log)
	if err := run(port, log); err != nil {
		log.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run(port string, log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := pg.Connect(ctx)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err := pg.Exec(ctx, pool, payment.DDL...); err != nil {
		return err
	}

	pub, err := events.PublisherFromEnv(ctx)
	if err != nil {
		return err
	}
	consumer, err := events.ConsumerFromEnv(ctx, payment.ConsumerName)
	if err != nil {
		return err
	}

	svc := payment.NewService(payment.NewPGStore(pool), pub, log)

	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		return httpx.Run(gctx, httpx.NewServer(":"+port, payment.Routes(svc, log)), log)
	})
	g.Go(func() error {
		if err := consumer.Run(gctx, svc.HandleEvent); err != nil {
			return fmt.Errorf("consumer: %w", err)
		}
		return nil
	})
	return g.Wait()
}
