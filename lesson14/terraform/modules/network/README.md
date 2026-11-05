# Network

VPC with one public and one private /24 subnet per AZ, an internet gateway, and NAT gateway(s) in the public subnets. Public subnets route `0.0.0.0/0` to the IGW and assign public IPs. Each AZ has its own private route table that sends `0.0.0.0/0` to a NAT gateway. With `single_nat_gateway = true` (the default) every table points at one NAT, which is cheaper. With `false`, each AZ gets its own NAT, so private egress keeps working when one AZ fails. The VPC's default security group is managed with no rules, so nothing can use it by accident.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | Name prefix and `Name` tags |
| `cidr` | Required | VPC IPv4 CIDR; must be a `/16` network address with no host bits (subnets are `cidrsubnet(cidr, 8, …)`) |
| `azs` | Required | 2–10 distinct AZs; public subnets `x.x.1.0/24…`, private `x.x.11.0/24…` |
| `single_nat_gateway` | `true` | One NAT for all private subnets (`true`) or one per AZ (`false`) |

| Output | Use |
| --- | --- |
| `vpc_id` | Security groups, ALB target groups |
| `vpc_cidr` | Security group rules for traffic from inside the VPC |
| `public_subnet_ids` | ALB (AZ order) |
| `private_subnet_ids` | ECS services, RDS subnet group (AZ order) |
| `nat_gateway_ids` | Checking egress; one element when `single_nat_gateway = true` |

```hcl
module "network" {
  source             = "../../modules/network"
  name               = "lesson14-dev"
  cidr               = "10.0.0.0/16"
  azs                = ["ap-southeast-1a", "ap-southeast-1b"]
  single_nat_gateway = true # dev: one NAT is enough
}
```

Tests: [`tests/subnets.tftest.hcl`](tests/subnets.tftest.hcl).
