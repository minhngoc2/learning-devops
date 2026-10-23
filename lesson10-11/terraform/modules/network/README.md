# Network

VPC with one public and one private /24 subnet per AZ, an internet gateway, a public route table (`0.0.0.0/0` → IGW) and a private route table with only the local route. The VPC's default security group is managed with no rules, so nothing can use it by accident. There is no NAT gateway: tasks use public subnets with public IPs, and RDS needs no egress.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | Name prefix and `Name` tags |
| `cidr` | Required | VPC IPv4 CIDR; must be a `/16` network address with no host bits (subnets are `cidrsubnet(cidr, 8, …)`) |
| `azs` | Required | 2–10 distinct AZs; public subnets `x.x.1.0/24…`, private `x.x.11.0/24…` |

| Output | Use |
| --- | --- |
| `vpc_id` | Security groups, ALB target group |
| `public_subnet_ids` | ECS tasks, ALB |
| `private_subnet_ids` | RDS subnet group |

```hcl
module "network" {
  source = "../../modules/network"
  name   = "lesson10-11-dev"
  cidr   = "10.0.0.0/16"
  azs    = ["ap-southeast-1a", "ap-southeast-1b"] # the roots pin these via var.azs
}
```

Why two tiers: the database lives where no route reaches the internet, while the API stays reachable. Tests: [`tests/subnets.tftest.hcl`](tests/subnets.tftest.hcl).
