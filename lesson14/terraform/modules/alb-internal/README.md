# Internal ALB

Internal (VPC-only) Application Load Balancer that path-routes to one IP-type target group per service. Every listener rule needs **two** matches: the service's path and an `X-Origin-Verify` header equal to the secret CloudFront injects. Anything else (wrong path, missing or wrong header) gets the listener's default `403 {"error":"forbidden"}`. The security group allows port 80 in and the container port out, both only to the VPC CIDR.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | ALB name and target-group prefix; ≤ 24 alphanumeric/hyphen chars, no `internal-` prefix. Target groups are `<name>-<service>` (≤ 32) |
| `vpc_id` | Required | VPC for the ALB and targets |
| `vpc_cidr` | Required | IPv4 CIDR: port 80 source and target-port egress destination |
| `subnet_ids` | Required | ≥ 2 distinct private subnets in different AZs |
| `container_port` | `8080` | Target and health-check port (1–65535) |
| `health_check_path` | `"/health"` | Health check (matcher 200, every 15 s); must start with `/` |
| `origin_verify_secret` | Required | Sensitive; ≥ 16 chars; required `X-Origin-Verify` value |
| `services` | Required | Map service → `{ path_pattern, priority }`; lowercase keys, unique priorities 1–50000 |

| Output | Use |
| --- | --- |
| `alb_arn` | Reference the ALB |
| `alb_arn_suffix` | CloudWatch `LoadBalancer` dimension |
| `dns_name` | Internal DNS name (resolves only inside the VPC) |
| `listener_arn` | API Gateway VPC Link `integration_uri` |
| `security_group_id` | Allow on the container port in ECS service SGs |
| `target_group_arns` | Map service → ARN for ECS `load_balancer` (ready once the rules exist) |
| `target_group_arn_suffixes` | Map service → CloudWatch `TargetGroup` dimension |

```hcl
module "alb" {
  source               = "../../modules/alb-internal"
  name                 = "l14-dev"
  vpc_id               = module.network.vpc_id
  vpc_cidr             = module.network.vpc_cidr
  subnet_ids           = module.network.private_subnet_ids
  origin_verify_secret = random_password.origin_verify.result
  services = {
    user = { path_pattern = "/api/users*", priority = 10 }
    cart = { path_pattern = "/api/cart*", priority = 30 }
  }
}
```

Tests: [`tests/routing.tftest.hcl`](tests/routing.tftest.hcl).
