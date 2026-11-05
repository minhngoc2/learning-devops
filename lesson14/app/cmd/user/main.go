// User Service: register and login against Cognito (AUTH_MODE=cognito) or an in-memory stand-in
// (AUTH_MODE=local, compose only), with the Customer profile in the users schema.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"

	"github.com/minhngoc2/learning-devops/lesson14/internal/config"
	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
	"github.com/minhngoc2/learning-devops/lesson14/internal/pg"
	"github.com/minhngoc2/learning-devops/lesson14/internal/user"
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

	auth, err := newAuth(ctx, log)
	if err != nil {
		return err
	}

	pool, err := pg.Connect(ctx)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err := pg.Exec(ctx, pool, user.DDL...); err != nil {
		return err
	}

	routes := user.Routes(auth, user.NewPGStore(pool), log)
	return httpx.Run(ctx, httpx.NewServer(":"+port, routes), log)
}

func newAuth(ctx context.Context, log *slog.Logger) (user.Auth, error) {
	switch mode := config.Get("AUTH_MODE", "cognito"); mode {
	case "local":
		log.Warn("AUTH_MODE=local: accounts are in memory and tokens are unsigned; never use on AWS")
		return user.NewLocalAuth(), nil
	case "cognito":
		poolID, clientID := config.Get("COGNITO_USER_POOL_ID", ""), config.Get("COGNITO_CLIENT_ID", "")
		if poolID == "" || clientID == "" {
			return nil, errors.New("AUTH_MODE=cognito needs COGNITO_USER_POOL_ID and COGNITO_CLIENT_ID")
		}
		cfg, err := awsconfig.LoadDefaultConfig(ctx)
		if err != nil {
			return nil, fmt.Errorf("aws config: %w", err)
		}
		return user.NewCognitoAuth(cognitoidentityprovider.NewFromConfig(cfg), poolID, clientID), nil
	default:
		return nil, fmt.Errorf("AUTH_MODE must be cognito or local, got %q", mode)
	}
}
