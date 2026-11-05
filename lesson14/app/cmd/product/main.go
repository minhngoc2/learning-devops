// Product Service: the catalogue in the products schema. It never calls S3: the seed script uploads images
// and passes their keys; image_url is PUBLIC_BASE_URL + "/images/" + key.
package main

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/minhngoc2/learning-devops/lesson14/internal/config"
	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
	"github.com/minhngoc2/learning-devops/lesson14/internal/pg"
	"github.com/minhngoc2/learning-devops/lesson14/internal/product"
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

	baseURL := config.Get("PUBLIC_BASE_URL", "")
	if baseURL == "" {
		return errors.New("PUBLIC_BASE_URL is not set")
	}

	pool, err := pg.Connect(ctx)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err := pg.Exec(ctx, pool, product.DDL...); err != nil {
		return err
	}

	routes := product.Routes(product.NewPGStore(pool), baseURL, log)
	return httpx.Run(ctx, httpx.NewServer(":"+port, routes), log)
}
