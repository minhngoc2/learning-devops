// Notification Service: emails customers about order events from its queue. It serves only /health.
// NOTIFY_MODE=log writes the emails to the log; NOTIFY_MODE=ses sends them from NOTIFY_FROM.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sesv2"
	"golang.org/x/sync/errgroup"

	"github.com/minhngoc2/learning-devops/lesson14/internal/config"
	"github.com/minhngoc2/learning-devops/lesson14/internal/events"
	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
	"github.com/minhngoc2/learning-devops/lesson14/internal/notification"
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

	sender, err := newSender(ctx, log)
	if err != nil {
		return err
	}
	consumer, err := events.ConsumerFromEnv(ctx, notification.ConsumerName)
	if err != nil {
		return err
	}
	svc := notification.NewService(sender, log)

	mux := http.NewServeMux()
	mux.Handle("GET /health", httpx.Health())

	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		return httpx.Run(gctx, httpx.NewServer(":"+port, httpx.Logging(log, mux)), log)
	})
	g.Go(func() error {
		if err := consumer.Run(gctx, svc.HandleEvent); err != nil {
			return fmt.Errorf("consumer: %w", err)
		}
		return nil
	})
	return g.Wait()
}

func newSender(ctx context.Context, log *slog.Logger) (notification.Sender, error) {
	switch mode := config.Get("NOTIFY_MODE", "log"); mode {
	case "log":
		return notification.NewLogSender(log), nil
	case "ses":
		from := config.Get("NOTIFY_FROM", "")
		if from == "" {
			return nil, errors.New("NOTIFY_MODE=ses needs NOTIFY_FROM")
		}
		cfg, err := awsconfig.LoadDefaultConfig(ctx)
		if err != nil {
			return nil, fmt.Errorf("aws config: %w", err)
		}
		return notification.NewSESSender(sesv2.NewFromConfig(cfg), from), nil
	default:
		return nil, fmt.Errorf("NOTIFY_MODE must be log or ses, got %q", mode)
	}
}
