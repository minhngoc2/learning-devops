# Lesson 14: E-commerce microservices on AWS

A small online shop split into six Go microservices on ECS Fargate, with a Nuxt storefront, Cognito sign-in, an event-driven order flow on SNS/SQS, PostgreSQL and DynamoDB, all behind one CloudFront distribution with WAF. Terraform deploys everything, with state in S3.

![Go 1.27.3](https://img.shields.io/badge/Go-1.27.3-00ADD8?logo=go&logoColor=white)
![Nuxt 4](https://img.shields.io/badge/Nuxt-4-00DC82?logo=nuxt&logoColor=white)
![Terraform 1.10+](https://img.shields.io/badge/Terraform-%E2%89%A5%201.10-7B42BC?logo=terraform&logoColor=white)
![go test 13 packages](https://img.shields.io/badge/go%20test-13%20packages-brightgreen)
![terraform test 66/66](https://img.shields.io/badge/terraform%20test-66%2F66-brightgreen)
![checkov 449/449](https://img.shields.io/badge/checkov-449%2F449-brightgreen)

- **[Quickstart](quickstart.md)**: setup, local run, offline checks, deploy, scenario demos, release, cleanup
- **[Local guide](docs/README.md)** (gitignored, local copies only): how each AWS service and the order flow work
- Modules: [state-bucket](terraform/modules/state-bucket/README.md) · [network](terraform/modules/network/README.md) · [ecr](terraform/modules/ecr/README.md) · [ecs-cluster](terraform/modules/ecs-cluster/README.md) · [ecs-service](terraform/modules/ecs-service/README.md) · [alb-internal](terraform/modules/alb-internal/README.md) · [api-gateway](terraform/modules/api-gateway/README.md) · [cognito](terraform/modules/cognito/README.md) · [rds-postgres](terraform/modules/rds-postgres/README.md) · [dynamodb-table](terraform/modules/dynamodb-table/README.md) · [messaging](terraform/modules/messaging/README.md) · [s3-cloudfront](terraform/modules/s3-cloudfront/README.md) · [waf](terraform/modules/waf/README.md) · [observability](terraform/modules/observability/README.md)

## Architecture

**Browser → CloudFront + WAF → (S3 storefront · S3 images · API Gateway → VPC Link → internal ALB) → six ECS Fargate services → RDS PostgreSQL · DynamoDB · SNS/SQS · Cognito · SES**

![Lesson 14 architecture: the browser reaches one CloudFront distribution protected by a WAF web ACL; CloudFront serves the storefront and product images from two private S3 buckets and forwards /api/* to an API Gateway HTTP API with a Cognito JWT authorizer; a VPC Link connects API Gateway to an internal ALB in the private subnets of two availability zones, which path-routes to the user, product, cart, order and payment services on ECS Fargate; the notification worker reads its own SQS queue; order and payment publish order events to an SNS topic that fans out to three SQS queues with dead-letter queues; user, product, order and payment keep their data in one RDS PostgreSQL instance with a schema per service, and cart uses a DynamoDB table](architecture.png)

- **Edge:** CloudFront serves the storefront and images from S3 and sends `/api/*` to API Gateway. WAF uses AWS managed rules and a rate limit.
- **API:** API Gateway HTTP API with throttling and a Cognito JWT authorizer. It sets the customer identity headers from the token, so services can trust them.
- **Private origin:** services have no public address. The ALB accepts only requests that carry CloudFront's secret `X-Origin-Verify` header.
- **Services:** `user`, `product`, `cart`, `order`, `payment`, `notification` on ARM64 Fargate. Each has its own role and CPU autoscaling from 1 to 4 tasks, and rolling deploys roll back on failure.
- **Data:** one RDS PostgreSQL instance with a schema per service, plus a DynamoDB cart table.
- **Events:** checkout creates a `PENDING_PAYMENT` order. `OrderCreated` → Payment → `PaymentSucceeded`/`PaymentFailed` → Order and Notification, through SNS and one SQS queue (with a DLQ) per consumer.

## Project layout

```text
app/                  Go module: six services, db-init, localbus, compose.yaml
storefront/           Nuxt 4 static SPA, uploaded to S3
terraform/bootstrap/  S3 state bucket (run once)
terraform/environments/dev/  The stack, composing all 14 modules
terraform/modules/    14 modules, each with a README and mocked tests
scripts/              build-push, run-db-init, seed, check-release
seed/                 Demo products and images
ci/                   Sample GitHub Actions pipeline (not wired)
```

## The six scenarios

| Scenario | Answer in this stack | Demo |
| --- | --- | --- |
| 10× traffic on sale day | CloudFront caching, API throttling, ECS autoscaling, on-demand DynamoDB, SQS buffering | Prose |
| One service is down | Only that service's paths fail. Its events wait in its queue | [10.5](quickstart.md#105-one-service-is-down) |
| Email is failing | Retries, then the DLQ. The order is still `PAID` | [10.1](quickstart.md#101-email-is-down-pause-notification) |
| Database fails in one AZ | Two-AZ subnets. `multi_az = true` adds an RDS standby | [10.6](quickstart.md#106-database-fails-in-one-az-prose) |
| Release with little downtime | Immutable tags, rolling deploy, circuit breaker, `check-release.sh` | [11](quickstart.md#11-release-v2) |
| Abnormal requests | WAF rules and rate limit, origin check, throttling, alarms | [10.3](quickstart.md#103-direct-execute-api-call-is-refused), [10.4](quickstart.md#104-waf-rate-limit) |

> [!CAUTION]
> The stack is billed hourly (about $4/day). It includes a NAT gateway, RDS, an ALB, six Fargate tasks and WAF. Always [clean up](quickstart.md#12-cleanup) when you finish, and never commit `*.tfstate`, `*.tfvars` or `dev.backend.hcl`.
