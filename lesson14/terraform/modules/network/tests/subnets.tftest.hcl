# Mocked AWS: no credentials or real resources.
mock_provider "aws" {}

variables {
  name = "test"
  cidr = "10.0.0.0/16"
  azs  = ["ap-southeast-1a", "ap-southeast-1b"]
}

run "two_az_single_nat" {
  command = apply # route blocks and NAT IDs are only known after (mocked) apply

  assert {
    condition     = length(output.public_subnet_ids) == 2 && length(output.private_subnet_ids) == 2
    error_message = "Two AZs must give two public and two private subnets."
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(output.nat_gateway_ids) == 1
    error_message = "single_nat_gateway (default true) must create exactly one NAT gateway."
  }
  assert {
    condition     = aws_nat_gateway.this[0].subnet_id == output.public_subnet_ids[0]
    error_message = "The NAT gateway must sit in the first public subnet."
  }
  assert {
    condition = alltrue([
      for az in var.azs : one(aws_route_table.private[az].route).nat_gateway_id == aws_nat_gateway.this[0].id
    ])
    error_message = "Every private route table must send 0.0.0.0/0 to the single NAT gateway."
  }
  assert {
    condition     = one(aws_route_table.public.route).gateway_id == aws_internet_gateway.main.id
    error_message = "The public route table must send 0.0.0.0/0 to the internet gateway."
  }
  assert {
    condition     = length(aws_default_security_group.default.ingress) == 0 && length(aws_default_security_group.default.egress) == 0
    error_message = "The VPC default security group must allow nothing."
  }
}

run "nat_per_az" {
  command = apply
  variables {
    single_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2 && length(output.nat_gateway_ids) == 2
    error_message = "single_nat_gateway = false must create one NAT gateway per AZ."
  }
  assert {
    condition = alltrue([
      for i, az in var.azs : aws_nat_gateway.this[i].subnet_id == output.public_subnet_ids[i]
    ])
    error_message = "Each NAT gateway must sit in the public subnet of its own AZ."
  }
  assert {
    condition = alltrue([
      for i, az in var.azs : one(aws_route_table.private[az].route).nat_gateway_id == aws_nat_gateway.this[i].id
    ])
    error_message = "Each private route table must send 0.0.0.0/0 to the NAT gateway in its own AZ."
  }
}

run "cidr_layout" {
  command = plan

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
    condition = (
      alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch]) &&
      !anytrue([for s in aws_subnet.private : s.map_public_ip_on_launch])
    )
    error_message = "Only public subnets may assign public IPs on launch."
  }
}

# One value per variable per run, so each run pairs one bad cidr with one bad azs list.
run "reject_bad_cidr" {
  command = plan
  variables {
    cidr = "10.0.0.0/20"       # not a /16
    azs  = ["ap-southeast-1a"] # one AZ
  }
  expect_failures = [var.cidr, var.azs]
}

run "reject_bad_azs" {
  command = plan
  variables {
    cidr = "10.0.1.0/16"                          # host bits set
    azs  = ["ap-southeast-1a", "ap-southeast-1a"] # duplicates
  }
  expect_failures = [var.cidr, var.azs]
}
