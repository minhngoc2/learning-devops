// Sample Go API for AWS Lambda behind an API Gateway HTTP API.
// API Gateway sends every request as an APIGatewayV2HTTPRequest event (payload format 2.0);
// the handler returns an APIGatewayV2HTTPResponse that API Gateway turns back into HTTP.
package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

// Init phase: runs once per execution environment (cold start), then reused by warm invocations.
var greeting = envOr("GREETING", "Hello")

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// handler routes on RouteKey ("METHOD /path"), which API Gateway fills from the matched route.
func handler(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	slog.Info("request", "route", req.RouteKey, "request_id", req.RequestContext.RequestID)

	switch req.RouteKey {
	case "GET /health":
		return reply(http.StatusOK, map[string]string{"status": "ok"}), nil
	case "GET /hello":
		name := req.QueryStringParameters["name"]
		if name == "" {
			name = "world"
		}
		return reply(http.StatusOK, map[string]string{"message": greeting + ", " + name + "!"}), nil
	case "POST /echo":
		raw := []byte(req.Body)
		if req.IsBase64Encoded { // API Gateway base64-encodes bodies it does not treat as text
			raw, _ = base64.StdEncoding.DecodeString(req.Body) // bad base64 → invalid JSON → 400 below
		}
		var body map[string]any
		if err := json.Unmarshal(raw, &body); err != nil || body == nil { // body == nil: the JSON was null
			return reply(http.StatusBadRequest, map[string]string{"error": "body must be a JSON object"}), nil
		}
		return reply(http.StatusOK, map[string]any{"echo": body}), nil
	default:
		return reply(http.StatusNotFound, map[string]string{"error": "route not found"}), nil
	}
}

func reply(status int, v any) events.APIGatewayV2HTTPResponse {
	b, _ := json.Marshal(v) // ponytail: only maps of strings/JSON values reach here, Marshal cannot fail
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(b),
	}
}

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	lambda.Start(handler)
}
