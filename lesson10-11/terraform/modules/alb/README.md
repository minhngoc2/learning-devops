# Application Load Balancer

Public HTTP ALB on port 80 for ECS tasks: its own security group (ingress only from `allowed_cidr`, egress only to the container port inside the VPC), an **IP** target group (required for Fargate `awsvpc` tasks) whose health check calls `/ready`, and a listener forwarding to it. Malformed headers are dropped. Gives clients one stable URL while tasks and their IPs change.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | ≤ 32 alphanumerics/hyphens, single hyphens only and none at the edges, no `internal-` prefix |
| `vpc_id` | Required | VPC of the ALB and targets |
| `vpc_cidr` | Required | IPv4 CIDR for target-port egress |
| `subnet_ids` | Required | At least two distinct public subnets in different AZs |
| `allowed_cidr` | Required | IPv4 CIDR allowed on port 80 (your `/32`) |
| `container_port` | `8080` | Target and health-check port, 1–65535 |

| Output | Use |
| --- | --- |
| `security_group_id` | The only source the ECS task SG accepts |
| `target_group_arn` | ECS `load_balancer` input, release checks |
| `api_url` | `http://<alb-dns-name>` |

HTTP only: HTTPS needs a domain and ACM certificate (a production gap). Example: the [staging root](../../environments/staging/main.tf). Tests: [`tests/routing.tftest.hcl`](tests/routing.tftest.hcl).
