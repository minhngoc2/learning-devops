# Observability

One ops SNS topic (`<name>-ops`, optional email subscription) that every alarm notifies on ALARM and OK, the alarm set from the spec, and one CloudWatch dashboard. Alarms: ALB target 5xx rate > 5 % (metric math, 5 × 1 min), ALB p95 `TargetResponseTime` > 1 s (5 × 1 min), one per DLQ when a message is visible (1 min), one per service when Container Insights `RunningTaskCount` averages below its desired count (5 × 1 min), RDS CPU > 80 % (2 × 5 min), RDS connections > 80 % of `db_max_connections`, and API Gateway 5xx rate > 1 %. For 6 services and 3 DLQs that is 14 alarms. The dashboard has five rows, each a `## ` heading: Edge (CloudFront requests and 5xx rate, WAF blocked requests; these widgets read `us-east-1`), API, Services, Data (RDS, plus DynamoDB tables found by a `SEARCH` on the name prefix) and Queues (main queues and DLQs).

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | Topic, alarm and dashboard prefix |
| `aws_region` | Required | Region of the regional metrics and the dashboard URL |
| `alb_arn_suffix` | Required | ALB `LoadBalancer` dimension |
| `target_group_arn_suffixes` | Required | Map service → `TargetGroup` dimension (per-service latency widget) |
| `cluster_name` | Required | ECS `ClusterName` dimension (Container Insights on) |
| `service_names` | Required | Map service → ECS service name; one under-desired alarm each |
| `desired_counts` | Required | Map service → desired tasks; same keys as `service_names`, whole numbers ≥ 0 |
| `db_identifier` | Required | RDS `DBInstanceIdentifier` |
| `db_max_connections` | Required | Connections alarm threshold = `floor(0.8 × value)` |
| `dlq_names` | Required | Map consumer → DLQ name; main queue = name without `-dlq` |
| `api_id` | Required | API Gateway `ApiId` |
| `web_acl_name` | Required | WAF `WebACL` dimension (us-east-1 widget) |
| `distribution_id` | Required | CloudFront `DistributionId` (us-east-1 widgets) |
| `alarm_email` | `null` | Email subscription to the topic (confirm it); `null` = none |

| Output | Use |
| --- | --- |
| `ops_topic_arn` | waf `ops_topic_arn`, other alarms |
| `dashboard_name` | Reference the dashboard |
| `dashboard_url` | Open the dashboard in the console |

```hcl
module "observability" {
  source                    = "../../modules/observability"
  name                      = "lesson14-dev"
  aws_region                = var.aws_region
  alb_arn_suffix            = module.alb.alb_arn_suffix
  target_group_arn_suffixes = module.alb.target_group_arn_suffixes
  cluster_name              = module.cluster.cluster_name
  service_names             = { for k, s in module.service : k => s.service_name }
  desired_counts            = { for k in keys(module.service) : k => 1 }
  db_identifier             = "lesson14-dev"
  db_max_connections        = module.db.max_connections_estimate
  dlq_names                 = module.messaging.dlq_names
  api_id                    = module.api.api_id
  web_acl_name              = "lesson14-dev"
  distribution_id           = module.edge.distribution_id
  alarm_email               = var.alarm_email
}
```

Tests: [`tests/observability.tftest.hcl`](tests/observability.tftest.hcl).
