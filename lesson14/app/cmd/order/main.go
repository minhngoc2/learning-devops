// Order Service: checkout over HTTP, payment outcomes from its queue. Both loops run under one signal
// context; when either fails, the other is stopped and the task exits so ECS replaces it.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"golang.org/x/sync/errgroup"

	"github.com/minhngoc2/learning-devops/lesson14/internal/config"
	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
	"github.com/minhngoc2/learning-devops/lesson14/internal/order"
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

	albURL := config.Get("ALB_URL", "")
	if albURL == "" {
		return errors.New("ALB_URL is not set")
	}

	pool, err := pg.Connect(ctx)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err := pg.Exec(ctx, pool, order.DDL...); err != nil {
		return err
	}

	pub, err := events.PublisherFromEnv(ctx)
	if err != nil {
		return err
	}
	consumer, err := events.ConsumerFromEnv(ctx, order.ConsumerName)
	if err != nil {
		return err
	}

	cartClient, productClient := order.NewHTTPClients(albURL, config.Get("ORIGIN_VERIFY", ""))
	svc := order.NewService(order.NewPGStore(pool), cartClient, productClient, pub, log)

	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		return httpx.Run(gctx, httpx.NewServer(":"+port, order.Routes(svc, log)), log)
	})
	g.Go(func() error {
		if err := order.Consume(gctx, consumer, svc); err != nil {
			return fmt.Errorf("consumer: %w", err)
		}
		return nil
	})
	return g.Wait()
}
