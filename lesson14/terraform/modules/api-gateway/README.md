# API Gateway HTTP API

API Gateway **HTTP API** that proxies every route through a VPC Link to one internal ALB listener (`HTTP_PROXY`, payload `1.0`). Protected routes need a valid JWT (Cognito) and go through an integration that **overwrites** `X-Customer-Sub` / `X-Customer-Email` from the token claims. Public routes skip auth and go through an integration that **removes** both headers, so services can trust them. The `$default` stage auto-deploys, throttles, and writes JSON access logs (including authorizer errors).

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | API and VPC Link name, `/aws/apigateway/<name>` log group |
| `vpc_link_subnet_ids` | Required | ≥ 2 distinct private subnets for the VPC Link ENIs |
| `vpc_link_security_group_id` | Required | SG on the VPC Link ENIs; must reach the ALB on port 80 |
| `listener_arn` | Required | ALB listener ARN both integrations target |
| `jwt_issuer` | Required | `https://` issuer URL (Cognito `issuer` output) |
| `jwt_audience` | Required | Non-empty list of accepted client IDs |
| `public_routes` | `[]` | Route keys `"METHOD /path"` without auth |
| `protected_routes` | `[]` | Route keys `"METHOD /path"` requiring a JWT; must not overlap `public_routes` |
| `throttling_burst_limit` | `100` | Burst requests (≥ 0) |
| `throttling_rate_limit` | `50` | Requests per second (≥ 0) |
| `log_retention_days` | `7` | Access-log retention; a CloudWatch value (0 = never expire) |

| Output | Use |
| --- | --- |
| `api_id` | Reference the API |
| `api_endpoint` | `https://<id>.execute-api.<region>.amazonaws.com` |
| `api_host` | Endpoint without scheme: CloudFront origin `domain_name` |
| `execution_arn` | IAM / permission `source_arn` conditions |
| `access_log_group_name` | Tail access logs |

```hcl
module "api" {
  source                     = "../../modules/api-gateway"
  name                       = "lesson14-dev"
  vpc_link_subnet_ids        = module.network.private_subnet_ids
  vpc_link_security_group_id = aws_security_group.vpc_link.id
  listener_arn               = module.alb.listener_arn
  jwt_issuer                 = module.cognito.issuer
  jwt_audience               = [module.cognito.client_id]
  public_routes              = ["POST /api/users/register", "GET /api/products"]
  protected_routes           = ["GET /api/users/me", "ANY /api/cart/{proxy+}"]
}
```

Tests: [`tests/routes.tftest.hcl`](tests/routes.tftest.hcl).
