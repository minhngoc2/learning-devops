# Lesson 13: Go on AWS Lambda behind API Gateway

A Go JSON API on AWS Lambda with a public HTTPS URL from API Gateway, deployed by Terraform with remote S3 state.

![Go 1.27](https://img.shields.io/badge/Go-1.27-00ADD8?logo=go&logoColor=white)
![Terraform 1.10+](https://img.shields.io/badge/Terraform-%E2%89%A5%201.10-7B42BC?logo=terraform&logoColor=white)
![terraform test 12/12](https://img.shields.io/badge/terraform%20test-12%2F12-brightgreen)
![checkov 32/32](https://img.shields.io/badge/checkov-32%2F32-brightgreen)

> [!NOTE]
> No servers, containers or VPC to manage. A `bootstrap` root creates this lesson's own S3 state bucket once, and the dev stack keeps its state there with S3-native locking.

- **[Quickstart](quickstart.md)**: bootstrap, build, deploy, verify, release, cleanup (with sample output)
- Modules: [state-bucket](terraform/modules/state-bucket/README.md) · [lambda-function](terraform/modules/lambda-function/README.md) · [api-gateway](terraform/modules/api-gateway/README.md)

## Architecture

**Client → API Gateway (HTTP API) → Lambda (Go, `provided.al2023`, arm64) → CloudWatch Logs**

![Lesson 13 architecture: client to API Gateway to Lambda inside AWS ap-southeast-1 with function and access logs, Lambda permission and execution role; below, laptop builds the zip, the Terraform dev root applies 12 resources and keeps state in the S3 bucket that the bootstrap root creates once](diagrams/architecture.png)

- **API Gateway:** Handles HTTPS, matches 3 routes, throttles requests (10 per second, bursts of 20), and writes JSON access logs.
- **Lambda:** Runs the Go `bootstrap` binary (128 MB, 10 s timeout) and routes on `RouteKey`.
- **IAM:** The function can only write logs, and only this API can call it.
- **State:** A private, versioned, encrypted, HTTPS-only bucket that can't be destroyed by accident. Old versions expire after 90 days.

Diagram source: [`diagrams/source/architecture.json`](diagrams/source/architecture.json) (Archify).

Terraform creates 6 resources in `bootstrap` (once) and 12 in `environments/dev`.

## API

| Request | Status | Body |
| --- | --- | --- |
| `GET /health` | `200` | `{"status":"ok"}` |
| `GET /hello?name=lesson13` | `200` | `{"message":"Hello, lesson13!"}` |
| `POST /echo` with `{"a":1}` | `200` | `{"echo":{"a":1}}` |
| `POST /echo` with invalid JSON or `null` | `400` | `{"error":"body must be a JSON object"}` |
| Any other route | `404` | From API Gateway; Lambda never runs |

## Results

| Check | Result |
| --- | --- |
| `go test` | Pass |
| `terraform fmt` / `validate` | Pass (bootstrap, dev, modules) |
| `terraform test` (mocked AWS) | 12 passed: dev 7, state-bucket 3, bootstrap 2 |
| TFLint (Terraform + AWS rulesets) | No issues |
| Checkov | 32 passed, 0 failed |
| Apply (dev stack) | 12 added, 0 changed, 0 destroyed |
| Live HTTPS checks | `200`, `200`, `400` and `404`, as expected |
| Code release | Only the function updated; new body live |
| Cold start / warm | 60 ms init, 62 ms billed / 2 ms billed, 23 MB of 128 MB used |

> [!TIP]
> Full commands and sample output, including both log groups, are in the [quickstart](quickstart.md).

## Lessons learned

> [!IMPORTANT]
> `terraform validate` and the mocked `terraform test` caught typos that looked fine at a glance, such as `apigateway.amazgnaws.com` and a log group missing its leading `/`. They failed before anything reached AWS.

- **`exec format error` on a Mac is a good sign.** It means the binary really was built for Lambda's Linux/arm64.
- **Unmatched routes never reach Lambda.** API Gateway answers them with a 404, and in this setup they did not show up in the access log either.
- **The state bucket outlives the stack.** `destroy` on dev leaves it in place on purpose; removing it is a separate, deliberate step.

> [!CAUTION]
> The API is public with no authentication; throttling is the only protection. Costs are near zero at lab scale, but always [clean up](quickstart.md#8-cleanup), and never commit `*.tfstate` or `dev.backend.hcl`.
