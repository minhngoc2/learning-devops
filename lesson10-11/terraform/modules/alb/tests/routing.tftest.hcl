mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:ap-southeast-1:111111111111:loadbalancer/app/api/0123456789abcdef"
      dns_name = "api.ap-southeast-1.elb.amazonaws.com"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-southeast-1:111111111111:targetgroup/api/0123456789abcdef"
    }
  }
}

variables {
  name         = "test-staging"
  vpc_id       = "vpc-0123456789abcdef0"
  vpc_cidr     = "10.1.0.0/16"
  subnet_ids   = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  allowed_cidr = "198.51.100.10/32"
}

run "http_readiness_routing" {
  command = plan
  assert {
    condition     = aws_lb_target_group.api.target_type == "ip" && aws_lb_target_group.api.health_check[0].path == "/ready" && aws_lb_target_group.api.health_check[0].matcher == "200"
    error_message = "Fargate targets require IP registration and readiness routing."
  }
  assert {
    condition     = aws_lb_listener.http.port == 80 && aws_lb_listener.http.protocol == "HTTP" && aws_vpc_security_group_ingress_rule.http.cidr_ipv4 == var.allowed_cidr
    error_message = "The lab entry point must be CIDR-restricted HTTP port 80."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.targets.cidr_ipv4 == var.vpc_cidr && aws_vpc_security_group_egress_rule.targets.to_port == 8080
    error_message = "ALB egress must be limited to the target port in the VPC."
  }
}

run "reject_ipv6_source" {
  command = plan
  variables {
    allowed_cidr = "::/0"
  }
  expect_failures = [var.allowed_cidr]
}

run "reject_bad_inputs" {
  command = plan
  variables {
    name           = "internal-a-name-that-is-far-too-long"
    vpc_cidr       = "not-a-cidr"
    subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef0"]
    container_port = 0
  }
  expect_failures = [var.name, var.vpc_cidr, var.subnet_ids, var.container_port]
}
