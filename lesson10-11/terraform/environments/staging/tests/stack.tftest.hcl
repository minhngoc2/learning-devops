mock_provider "aws" {}

run "isolated_staging_stack" {
  command = plan
  variables {
    allowed_cidr = "198.51.100.10/32"
  }
  assert {
    condition     = module.ecs.cluster_name == "lesson10-11-staging" && module.ecs.service_name == "lesson10-11-staging"
    error_message = "Staging must have separate service and cluster names."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.db_from_api.from_port == 5432 && aws_vpc_security_group_ingress_rule.db_from_api.cidr_ipv4 == null
    error_message = "Staging DB ingress must use the task SG, never a public CIDR."
  }
}

run "reject_bad_inputs" {
  command = plan
  variables {
    azs          = ["ap-southeast-1a", "ap-southeast-10a"]
    vpc_cidr     = "10.1.0.0/20"
    allowed_cidr = "::/0"
  }
  expect_failures = [var.azs, var.vpc_cidr, var.allowed_cidr]
}
