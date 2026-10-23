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

run "reject_bad_inputs" {
  command = plan
  variables {
    name               = "a-name-that-is-far-too-long-for-the-execution-role-name-x"
    subnet_ids         = []
    allowed_cidr       = "::/0"
    container_port     = 70000
    cpu                = 300
    desired_count      = -1
    log_retention_days = 10
  }
  # memory's rule reads var.cpu, so Terraform skips it while cpu is invalid; the next run covers memory.
  expect_failures = [var.name, var.subnet_ids, var.allowed_cidr, var.container_port, var.cpu, var.desired_count, var.log_retention_days]
}

run "reject_memory_not_allowed_for_cpu" {
  command = plan
  variables {
    allowed_cidr = "198.51.100.10/32"
    cpu          = 256
    memory       = 4096
  }
  expect_failures = [var.memory]
}

run "accept_larger_fargate_size" {
  command = plan
  variables {
    allowed_cidr = "198.51.100.10/32"
    cpu          = 1024
    memory       = 3072
  }
  assert {
    condition     = aws_ecs_task_definition.api.cpu == "1024" && aws_ecs_task_definition.api.memory == "3072"
    error_message = "A valid Fargate CPU/memory pair must reach the task definition."
  }
}
