# ECS service

One Fargate (ARM64) workload: task definition with a single container named `app` (port mappings, environment, Secrets Manager secrets, container health check every 30 s, `awslogs` to `/ecs/<name>` with stream prefix `app`), an execution role (`AmazonECSTaskExecutionRolePolicy` plus a `read-secrets` policy scoped to the referenced secrets), a task role for the app's own permissions (`task_policy_json`), and a security group (all egress; ingress on `container_port` only from `ingress_security_group_id`). With `create_service = true` it also runs an ECS service (rolling 100/200 %, circuit breaker with rollback, optional target-group registration with a 60 s grace period) and CPU target-tracking autoscaling between `min_count` and `max_count`. The service ignores later `desired_count` changes because autoscaling owns them. With `create_service = false` (db-init) only the task definition, roles, log group and security group are created; the SG still exists so the caller can allow it into the database.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | Service, family, SG, roles `<name>-execution`/`<name>-task`; 1–54 chars |
| `cluster_id`, `cluster_name` | Required | Cluster for the service and for the scaling resource ID |
| `vpc_id`, `subnet_ids` | Required | Task SG VPC; ≥ 1 private subnet (no public IP) |
| `image` | Required | Full ARM64 image reference |
| `container_port` | `8080` | App, target-group and ingress port (1–65535) |
| `cpu` / `memory` | `256` / `512` | Fargate size; memory must be valid for the cpu (e.g. 256 → 512/1024/2048) |
| `create_service` | `true` | `false` = task definition only, no service or autoscaling |
| `desired_count` | `1` | Initial tasks (≥ 0); ignored after creation |
| `min_count` / `max_count` | `1` / `4` | Autoscaling bounds; min ≥ 0, max ≥ min and ≥ 1 |
| `cpu_target` | `60` | Target average CPU % (0–100] |
| `environment` | `{}` | Plain env vars |
| `secrets` | `{}` | Env var → Secrets Manager ARN (optional `:key::` suffix) |
| `task_policy_json` | `null` | Inline task role policy; `null` = none |
| `ingress_security_group_id` | `null` | SG allowed on `container_port` (ALB SG); `null` = no ingress |
| `target_group_arn` | `null` | Register `app:<container_port>`; `null` = worker |
| `health_check_command` | `["CMD","/app","-healthcheck"]` | Container health check; starts with `CMD`/`CMD-SHELL` |
| `log_retention_days` | `7` | A CloudWatch Logs retention value |
| `enable_execute_command` | `false` | ECS Exec plus the SSM channel permissions on the task role |

| Output | Use |
| --- | --- |
| `service_name` | CloudWatch `ServiceName`; `null` without a service |
| `task_definition_arn` | `aws ecs run-task` (db-init) |
| `security_group_id` | Source for DB ingress rules |
| `task_role_name`, `task_role_arn` | Attach or reference app permissions |
| `execution_role_arn` | Reference the execution role |
| `log_group_name` | `aws logs tail` |
| `scalable_target_resource_id` | Extra scaling policies; `null` without a service |

```hcl
module "service" {
  source                    = "../../modules/ecs-service"
  name                      = "lesson14-dev-user"
  cluster_id                = module.cluster.cluster_id
  cluster_name              = module.cluster.cluster_name
  vpc_id                    = module.network.vpc_id
  subnet_ids                = module.network.private_subnet_ids
  image                     = "${module.ecr.repository_urls["user"]}:${var.image_tag}"
  target_group_arn          = module.alb.target_group_arns["user"]
  ingress_security_group_id = module.alb.security_group_id
  secrets                   = { DB_PASSWORD = "${module.db.secret_arn}:password::" }
}
```

Tests: [`tests/ecs_service.tftest.hcl`](tests/ecs_service.tftest.hcl).
