mock_provider "aws" {}

variables {
  name       = "test-api"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  image      = "111111111111.dkr.ecr.ap-southeast-1.amazonaws.com/api:v1"
}

run "dev_direct_access" {
  command = plan
  variables {
    allowed_cidr = "198.51.100.10/32"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.api.cidr_ipv4 == "198.51.100.10/32" && aws_vpc_security_group_ingress_rule.api.referenced_security_group_id == null
    error_message = "Dev must retain CIDR-based ingress without ALB SG access."
  }
  assert {
    condition     = length(aws_ecs_service.api.load_balancer) == 0
    error_message = "Dev must not gain a load balancer."
  }
}

run "staging_alb_access" {
  command = plan
  variables {
    desired_count = 2
    load_balancer = {
      security_group_id = "sg-0123456789abcdef0"
      target_group_arn  = "arn:aws:elasticloadbalancing:ap-southeast-1:111111111111:targetgroup/api/0123456789abcdef"
    }
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.api.cidr_ipv4 == null && aws_vpc_security_group_ingress_rule.api.referenced_security_group_id == "sg-0123456789abcdef0"
    error_message = "Staging ingress must accept the ALB SG only."
  }
  assert {
    condition     = one(aws_ecs_service.api.load_balancer).container_name == "api" && one(aws_ecs_service.api.load_balancer).container_port == 8080 && aws_ecs_service.api.health_check_grace_period_seconds == 60
    error_message = "ECS must register API port 8080 and allow startup grace."
  }
}

run "reject_missing_ingress_source" {
  command         = plan
  expect_failures = [aws_vpc_security_group_ingress_rule.api]
}
