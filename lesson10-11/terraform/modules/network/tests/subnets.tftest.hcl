mock_provider "aws" {}

variables {
  name = "test"
  cidr = "10.0.0.0/16"
  azs  = ["ap-southeast-1a", "ap-southeast-1b"]
}

run "public_and_private_subnets" {
  command = apply # route and default-SG rule blocks are computed sets, only known after (mocked) apply
  assert {
    condition = (
      aws_subnet.public["ap-southeast-1a"].cidr_block == "10.0.1.0/24" &&
      aws_subnet.public["ap-southeast-1b"].cidr_block == "10.0.2.0/24" &&
      aws_subnet.private["ap-southeast-1a"].cidr_block == "10.0.11.0/24" &&
      aws_subnet.private["ap-southeast-1b"].cidr_block == "10.0.12.0/24"
    )
    error_message = "Subnets must be carved as public x.x.1-2.0/24 and private x.x.11-12.0/24."
  }
  assert {
    condition     = one(aws_route_table.public.route).cidr_block == "0.0.0.0/0" && length(aws_route_table.private.route) == 0
    error_message = "Only the public route table may route to the internet."
  }
  assert {
    condition     = length(aws_default_security_group.default.ingress) == 0 && length(aws_default_security_group.default.egress) == 0
    error_message = "The VPC default security group must allow nothing."
  }
}

run "reject_bad_inputs" {
  command = plan
  variables {
    cidr = "10.0.0.0/20"
    azs  = ["ap-southeast-1a"]
  }
  expect_failures = [var.cidr, var.azs]
}

run "reject_ipv6_and_duplicate_azs" {
  command = plan
  variables {
    cidr = "2001:db8::/16"
    azs  = ["ap-southeast-1a", "ap-southeast-1a"]
  }
  expect_failures = [var.cidr, var.azs]
}

run "reject_cidr_with_host_bits" {
  command = plan
  variables {
    cidr = "10.0.5.0/16"
    azs  = ["ap-southeast-1a", "ap-southeast-1b"]
  }
  expect_failures = [var.cidr]
}
