# Lesson 14: E-commerce microservices on AWS

A small online shop split into six Go microservices on ECS Fargate, with a Nuxt storefront, Cognito sign-in, an event-driven order flow on SNS/SQS, PostgreSQL and DynamoDB, all behind one CloudFront distribution with WAF. Terraform deploys everything, with state in S3.

![Go 1.27.3](https://img.shields.io/badge/Go-1.27.3-00ADD8?logo=go&logoColor=white)
![Nuxt 4](https://img.shields.io/badge/Nuxt-4-00DC82?logo=nuxt&logoColor=white)
![Terraform 1.10+](https://img.shields.io/badge/Terraform-%E2%89%A5%201.10-7B42BC?logo=terraform&logoColor=white)
![go test 13 packages](https://img.shields.io/badge/go%20test-13%20packages-brightgreen)
![terraform test 66/66](https://img.shields.io/badge/terraform%20test-66%2F66-brightgreen)
![checkov 449/449](https://img.shields.io/badge/checkov-449%2F449-brightgreen)

> [!NOTE]
> This lesson is self-contained: it has its own `bootstrap` root for the state bucket and its own 14 modules, and it uses nothing from other lessons. Services have no public address. The only way in is CloudFront, and a secret header proves to the internal load balancer that a request came that way. Payment is asynchronous: an order is created as `PENDING_PAYMENT`, and events finish it.

- **[Quickstart](quickstart.md)**: bootstrap, local run, offline checks, deploy, seed, verify, six scenario demos, release, cleanup
- **[Local guide](docs/README.md)**: the chapters that explain every AWS service, the order flow and the six scenarios. It is a local, gitignored folder, so it exists only in a working copy that has it
- Modules: [state-bucket](terraform/modules/state-bucket/README.md) · [network](terraform/modules/network/README.md) · [ecr](terraform/modules/ecr/README.md) · [ecs-cluster](terraform/modules/ecs-cluster/README.md) · [ecs-service](terraform/modules/ecs-service/README.md) · [alb-internal](terraform/modules/alb-internal/README.md) · [api-gateway](terraform/modules/api-gateway/README.md) · [cognito](terraform/modules/cognito/README.md) · [rds-postgres](terraform/modules/rds-postgres/README.md) · [dynamodb-table](terraform/modules/dynamodb-table/README.md) · [messaging](terraform/modules/messaging/README.md) · [s3-cloudfront](terraform/modules/s3-cloudfront/README.md) · [waf](terraform/modules/waf/README.md) · [observability](terraform/modules/observability/README.md)

## Architecture

**Browser → CloudFront + WAF → (S3 storefront · S3 images · API Gateway → VPC Link → internal ALB) → six ECS Fargate services → RDS PostgreSQL · DynamoDB · SNS/SQS · Cognito · SES**

![Lesson 14 architecture: the browser reaches one CloudFront distribution protected by a WAF web ACL; CloudFront serves the storefront and product images from two private S3 buckets and forwards /api/* to an API Gateway HTTP API with a Cognito JWT authorizer; a VPC Link connects API Gateway to an internal ALB in the private subnets of two availability zones, which path-routes to the user, product, cart, order and payment services on ECS Fargate; the notification worker reads its own SQS queue; order and payment publish order events to an SNS topic that fans out to three SQS queues with dead-letter queues; user, product, order and payment keep their data in one RDS PostgreSQL instance with a schema per service, cart uses a DynamoDB table, user signs customers in with Cognito, notification emails through SES; CloudWatch collects logs, metrics, alarms and a dashboard](architecture.png)

| Part | Notes |
| --- | --- |
| Edge | One CloudFront distribution: `/` from the storefront bucket, `/images/*` from the images bucket, `/api/*` to API Gateway (not cached). The WAF web ACL (us-east-1) runs the AWS Common and Known Bad Inputs rule sets and blocks any IP above 2,000 requests per 5 minutes |
| API | API Gateway HTTP API, throttled to 50 req/s (burst 100), with JSON access logs. A Cognito JWT authorizer guards 9 of the 13 routes. Protected routes **overwrite** `X-Customer-Sub` and `X-Customer-Email` from the token, and public routes **remove** them, so services can trust both headers |
| Origin check | CloudFront adds a secret `X-Origin-Verify` header. Every ALB listener rule needs the path **and** that header, and anything else gets `403 {"error":"forbidden"}`. That is why the raw `execute-api` URL is refused |
| Services | `user`, `product`, `cart`, `order`, `payment`, `notification`: ARM64 Fargate tasks in private subnets, one task role each with only the permissions it needs, CPU autoscaling from 1 to 4 tasks, rolling deploys with circuit breaker and rollback; `terraform apply` waits for each service to be stable. `db-init` is a one-off task (schemas, roles, grants) that `terraform apply` runs before creating the services (`run_db_init`, default `true`) |
| Data | One RDS PostgreSQL 17 instance (`db.t4g.micro`) with a schema and login role per service (`users`, `products`, `orders`, `payments`). The cart is a DynamoDB table with a 7-day TTL. Product images live in S3 |
| Events | Order publishes `OrderCreated`. Payment consumes it and publishes `PaymentSucceeded` or `PaymentFailed`. Order and Notification consume the outcome. One SNS topic, one SQS queue per consumer with a filter on `event_type`, and a DLQ after 5 failed receives |
| Identity | Cognito user pool with email sign-in. User Service registers and confirms customers and returns the tokens. The storefront sends the ID token as `Bearer` |
| Email | Notification sends through SES when `notify_from_email` is set. Otherwise it writes each email to its log (`NOTIFY_MODE=log`) |
| Observability | A log group per service, Container Insights, a CloudWatch dashboard, and 14 regional alarms to an ops topic, plus a WAF alarm to a second topic in us-east-1 |
| State | A private, versioned, HTTPS-only S3 bucket from `terraform/bootstrap`, with S3-native locking |

## Project layout

```text
app/                       Go module: six services, db-init, localbus; compose.yaml for a local run
├── cmd/                   One main.go per binary (one Dockerfile, --build-arg SERVICE=<name>)
└── internal/              httpx, config, events, pg, ids, dbinit, and one package per service with its tests
storefront/                Nuxt 4 static SPA (pnpm), uploaded to S3
terraform/
├── bootstrap/             S3 state bucket (local state, run once)
├── environments/dev/      The stack: composes all modules, mocked tests
└── modules/               14 modules, each with a README and mocked tests
scripts/                   build-push, run-db-init, seed, check-release (+ offline test)
seed/                      Six demo products and their placeholder images
ci/                        Sample GitHub Actions pipeline (not wired)
```

## API

All routes are under the CloudFront URL. 🔒 = needs `Authorization: Bearer <id_token>`.

| Request | Status | Body |
| --- | --- | --- |
| `POST /api/users/register` `{email,password,display_name}` | `201` | The customer. `409` `email already registered` once the profile exists. A retry after a half-finished sign-up completes it and returns `201`. `400` when Cognito rejects the password |
| `POST /api/users/login` `{email,password}` | `200` | `{id_token,access_token,refresh_token,expires_in}`. `401` `invalid credentials`, also for an empty email or password |
| `GET /api/users/me` 🔒 | `200` | `{sub,email,display_name,created_at}` |
| `GET /api/products[?ids=a,b][&category=c]` | `200` | List of products with `price_cents`, `currency` (`VND`) and `image_url`. `400` for more than 100 distinct `ids` |
| `GET /api/products/{id}` | `200` | One product. `404` `product not found` |
| `POST /api/products` 🔒 | `201` | Seed/demo only. `409` for an existing id. `400` `currency must be VND` |
| `GET /api/cart` 🔒 | `200` | `{customer_sub,items:[{product_id,quantity}],updated_at}` |
| `PUT /api/cart/items/{productId}` 🔒 `{quantity}` | `200` | The cart. `0` removes the line. `400` outside 0–99. `422` `cart is full (max 100 lines)` for a new product on a 100-line cart |
| `DELETE /api/cart` 🔒 | `204` | Empty |
| `POST /api/orders` 🔒 | `201` | The order, `PENDING_PAYMENT`, prices copied at checkout. `422` `cart is empty` or `unknown product <id>` |
| `GET /api/orders` 🔒, `GET /api/orders/{id}` 🔒 | `200` | Your orders, newest first. Status ends as `PAID` or `PAYMENT_FAILED`. `404` for someone else's order |
| `GET /api/payments/{orderId}` 🔒 | `200` | `{id,order_id,amount_cents,status,reason,…}`. `404` until Payment has handled the order |
| Protected route without a valid token | `401` | From API Gateway; no service runs |
| Any other `/api/...` route | `404` | From API Gateway |
| The raw `execute-api` URL | `403` | `{"error":"forbidden"}` from the ALB (no `X-Origin-Verify`) |

Payment uses a fixed demo rule: a total whose cents end in `99` is declined with `card declined (demo rule: totals ending in 99)`. The seed product `p-0005` costs 9,999,999 cents, so ordering one of it alone fails.

## The six scenarios

| Scenario | Answer in this stack | Demo |
| --- | --- | --- |
| 10× traffic on sale day | CloudFront caches the storefront and images, API Gateway throttles, each service scales on CPU from 1 to 4 tasks, DynamoDB is on-demand, and SQS absorbs bursts between services | Prose |
| One service is down | Separate services and target groups: only that service's paths fail, and queued events wait | [Quickstart 10.5](quickstart.md#105-one-service-is-down) |
| Order created, email failing | `OrderCreated` waits in the notification queue, is retried, and goes to the DLQ after 5 tries. The order is still `PAID` | [Quickstart 10.1](quickstart.md#101-email-is-down-pause-notification) |
| Database fails in one AZ | Subnets in two AZs. Set `multi_az = true` for an RDS standby with automatic failover. DynamoDB is multi-AZ already | [Quickstart 10.6](quickstart.md#106-database-fails-in-one-az-prose) |
| New version with little downtime | Immutable image tags, rolling deploys at 100–200 %, circuit breaker with rollback, and `check-release.sh` | [Quickstart 11](quickstart.md#11-release-v2) |
| Abnormal requests | WAF managed rules and a rate rule, origin verification, API Gateway throttling, access logs and alarms | [Quickstart 10.3](quickstart.md#103-direct-execute-api-call-is-refused) and [10.4](quickstart.md#104-waf-rate-limit) |

## Results

| Check | Result |
| --- | --- |
| Go | `go test ./...` passes for 13 packages (the `cmd/*` service mains have no tests) |
| Storefront | `nuxi typecheck` clean; `pnpm generate` prerenders 9 routes into `storefront/.output/public` |
| Static checks | `fmt`, `validate` and TFLint clean. Checkov 449 passed, 0 failed |
| `terraform test` (mocked AWS) | 66 passed: bootstrap 2, dev root 8, modules 56 |
| Release check | `python3 scripts/test_check_release.py`: 4 tests pass with command stubs |
| Deploy | TODO: from the live run |
| Order flow and scenarios | TODO: from the live run |
| Release `v2` | TODO: from the live run |
| Cleanup | TODO: from the live run |

## Lessons learned

- **HTTP APIs cannot carry WAF.** WAF sits on CloudFront, so the raw `execute-api` URL would bypass it. A secret `X-Origin-Verify` header, checked by every ALB listener rule, closes that path.
- **CLOUDFRONT-scope WAF lives in us-east-1, and so do its metrics.** A CloudWatch alarm can notify only a topic in its own region, so the WAF alarm has its own ops topic in us-east-1, and `alarm_email` gets two confirmation emails.
- **No `custom_error_response` on the distribution.** It applies to every behaviour, so it would turn API `403`/`404` responses and WAF blocks into the storefront page. A CloudFront Function rewrites SPA paths to `/index.html` instead.
- **Identity headers must be set by the gateway, never by the client.** Protected integrations overwrite `X-Customer-Sub`/`X-Customer-Email` from the JWT, and public ones remove them.
- **The first deploy needs images before services.** ECR tags are immutable and the services reference `:<image_tag>`, so the repositories are created with a targeted apply, the images are pushed, and then the full stack is applied. That apply runs `db-init` before the services exist, so they find their roles on first start.
- **Autoscaling owns the task count.** `ecs-service` ignores `desired_count` after creation, so the scenario demos can pause a service without Terraform undoing it. Restore the scalable target afterwards, or the next plan shows drift.
- **TFLint `--config` must be absolute.** With `--recursive`, a relative path silently falls back to the default rules and skips the AWS checks.

> [!CAUTION]
> This stack bills by the hour while it exists: a NAT gateway, an RDS instance, an internal ALB, six Fargate tasks, and the WAF web ACL. The design target is around $4/day. Always [clean up](quickstart.md#12-cleanup) when you finish, and never commit `*.tfstate`, `*.tfvars` or `dev.backend.hcl`.
