mock_provider "aws" {}

run "dev_stack" {
  command = plan
  assert {
    condition     = module.ecs.cluster_name == "lesson10-11-dev" && module.ecs.service_name == "lesson10-11-dev"
    error_message = "Dev resources must be named <project>-dev."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.db_from_api.from_port == 5432 && aws_vpc_security_group_ingress_rule.db_from_api.cidr_ipv4 == null
    error_message = "Dev DB ingress must use the task SG, never a CIDR."
  }
}

run "reject_bad_inputs" {
  command = plan
  variables {
    azs          = ["ap-southeast-1a", "us-east-1a"]
    vpc_cidr     = "10.0.0.0/20"
    allowed_cidr = "::/0"
  }
  expect_failures = [var.azs, var.vpc_cidr, var.allowed_cidr]
}

run "reject_local_zone" {
  command = plan
  variables {
    aws_region = "us-east-1"
    azs        = ["us-east-1a", "us-east-1-bos-1a"]
  }
  expect_failures = [var.azs]
}
