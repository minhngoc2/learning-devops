# ECS cluster

Fargate-only ECS cluster with Container Insights (on by default) and the `FARGATE` and `FARGATE_SPOT` capacity providers. Services that set no strategy of their own run on `FARGATE` (weight 1).

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | Cluster name |
| `container_insights` | `true` | Per-task CPU/memory metrics in CloudWatch (billed as custom metrics) |

| Output | Use |
| --- | --- |
| `cluster_id` | `aws_ecs_service.cluster` |
| `cluster_arn` | IAM conditions, EventBridge targets |
| `cluster_name` | CloudWatch alarm dimensions, auto scaling resource IDs |

```hcl
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"
  name   = "lesson14-dev"
}
```

Tests: [`tests/cluster.tftest.hcl`](tests/cluster.tftest.hcl).
