// Cart Service: one DynamoDB item per customer. On ECS the table comes from Terraform; with
// DYNAMODB_ENDPOINT set (compose, DynamoDB Local) it creates the table on startup.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/minhngoc2/learning-devops/lesson14/internal/cart"
	"github.com/minhngoc2/learning-devops/lesson14/internal/config"
	"github.com/minhngoc2/learning-devops/lesson14/internal/httpx"
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

	table := config.Get("CART_TABLE", "")
	if table == "" {
		return errors.New("CART_TABLE is not set")
	}
	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("aws config: %w", err)
	}
	endpoint := config.Get("DYNAMODB_ENDPOINT", "")
	client := dynamodb.NewFromConfig(cfg, func(o *dynamodb.Options) {
		if endpoint != "" {
			o.BaseEndpoint = aws.String(endpoint)
		}
	})
	if endpoint != "" {
		if err := ensureLocalTable(ctx, client, table); err != nil {
			return err
		}
	}

	store := cart.NewDynamoStore(client, table, config.Int("CART_TTL_DAYS", 7))
	return httpx.Run(ctx, httpx.NewServer(":"+port, cart.Routes(store, log)), log)
}

// ensureLocalTable creates the table in DynamoDB Local. Never called on AWS, where the task role has no
// CreateTable permission and Terraform owns the table.
func ensureLocalTable(ctx context.Context, client *dynamodb.Client, table string) error {
	_, err := client.CreateTable(ctx, &dynamodb.CreateTableInput{
		TableName:            aws.String(table),
		BillingMode:          types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{{AttributeName: aws.String("customer_sub"), AttributeType: types.ScalarAttributeTypeS}},
		KeySchema:            []types.KeySchemaElement{{AttributeName: aws.String("customer_sub"), KeyType: types.KeyTypeHash}},
	})
	var inUse *types.ResourceInUseException
	if err != nil && !errors.As(err, &inUse) {
		return fmt.Errorf("create local table %s: %w", table, err)
	}
	return nil
}
