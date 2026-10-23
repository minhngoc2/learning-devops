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
| Static checks | `go test`, `fmt`, `validate`, TFLint pass; Checkov 32/32 |
| `terraform test` (mocked AWS) | 12 passed |
| Deploy | 12 resources; all live checks return the expected status |
| Release | 1 in-place change, new code live in 7 s at the same URL |
| Latency | Cold start 305 ms, warm 15–35 ms (2 ms billed) |
| Cleanup | 12 destroyed; state bucket kept |

## Lessons learned

- **Mocked tests catch typos for free.** `validate` and `terraform test` caught a misspelled service principal before anything reached AWS.
- **A release is just a new hash.** Rebuild the binary and only `source_code_hash` changes; no rebuild means `No changes`.
- **Unmatched routes never reach Lambda.** API Gateway returns the 404 itself, so it isn't in the function log.

> [!CAUTION]
> The API is public with no authentication; throttling is the only protection. Costs are near zero at lab scale, but always [clean up](quickstart.md#8-cleanup), and never commit `*.tfstate` or `dev.backend.hcl`.
