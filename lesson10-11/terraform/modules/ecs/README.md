# ECS Fargate service

Cluster, ARM64 Fargate task definition (one essential `api` container with an in-container health check), service with a deployment circuit breaker and automatic rollback, task security group, CloudWatch log group (`/ecs/<name>`), and the **execution role** ECS uses to pull the image, write logs and read the injected secrets. No task role: the app calls no AWS APIs.

Ingress has two modes: direct (`allowed_cidr`, dev) or behind an ALB (`load_balancer`, staging, which also registers the container and sets a 60 s health-check grace period). A precondition requires one of them.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | 1–54 letters/digits/`-`/`_` (role `<name>-execution` must fit IAM's 64) |
| `vpc_id` | Required | VPC for the task SG |
| `subnet_ids` | Required | At least one subnet |
| `image` | Required | Full image reference including tag |
| `assign_public_ip` | `false` | Needed in public subnets without NAT |
| `allowed_cidr` | `null` | IPv4 CIDR for direct access; ignored when `load_balancer` is set |
| `load_balancer` | `null` | `{ target_group_arn, security_group_id }` |
| `container_port` | `8080` | 1–65535 |
| `cpu` | `256` | Fargate size: 256, 512, 1024, 2048, 4096, 8192, 16384 |
| `memory` | `512` | Must be valid for `cpu` (256 → 512/1024/2048; 512 → 1024–4096; …) |
| `desired_count` | `1` | Whole number ≥ 0 |
| `environment` | `{}` | Plain env vars |
| `secrets` | `{}` | Env var → Secrets Manager `valueFrom` (ARN, optional `:json-key::`) |
| `log_retention_days` | `7` | A CloudWatch Logs retention value (0 = never expire) |

| Output | Use |
| --- | --- |
| `cluster_name`, `service_name` | CLI commands, release checks |
| `security_group_id` | Source for the DB ingress rule |

Example: the [dev root](../../environments/dev/main.tf) (direct) and [staging root](../../environments/staging/main.tf) (ALB). Tests: [`tests/ingress.tftest.hcl`](tests/ingress.tftest.hcl).
