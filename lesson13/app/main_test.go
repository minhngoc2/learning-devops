package main

import (
	"context"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandler(t *testing.T) {
	cases := []struct {
		name, route, body, query string
		status                   int
		want                     string
	}{
		{"health", "GET /health", "", "", 200, `{"status":"ok"}`},
		{"hello default", "GET /hello", "", "", 200, `{"message":"Hello, world!"}`},
		{"hello name", "GET /hello", "", "lesson13", 200, `{"message":"Hello, lesson13!"}`},
		{"echo", "POST /echo", `{"a":1}`, "", 200, `{"echo":{"a":1}}`},
		{"echo bad json", "POST /echo", `nope`, "", 400, `{"error":"body must be a JSON object"}`},
		{"echo null", "POST /echo", `null`, "", 400, `{"error":"body must be a JSON object"}`},
		{"echo array", "POST /echo", `[1,2]`, "", 400, `{"error":"body must be a JSON object"}`},
		{"unknown", "GET /nope", "", "", 404, `{"error":"route not found"}`},
	}
	t.Run("echo base64", func(t *testing.T) {
		req := events.APIGatewayV2HTTPRequest{RouteKey: "POST /echo", Body: "eyJhIjoxfQ==", IsBase64Encoded: true} // {"a":1}
		res, _ := handler(context.Background(), req)
		if res.StatusCode != 200 || res.Body != `{"echo":{"a":1}}` {
			t.Fatalf("got %d %s", res.StatusCode, res.Body)
		}
	})
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			req := events.APIGatewayV2HTTPRequest{RouteKey: c.route, Body: c.body}
			if c.query != "" {
				req.QueryStringParameters = map[string]string{"name": c.query}
			}
			res, err := handler(context.Background(), req)
			if err != nil {
				t.Fatal(err)
			}
			if res.StatusCode != c.status || res.Body != c.want {
				t.Fatalf("got %d %s, want %d %s", res.StatusCode, res.Body, c.status, c.want)
			}
			if res.Headers["Content-Type"] != "application/json" {
				t.Fatalf("missing JSON content type")
			}
		})
	}
}
