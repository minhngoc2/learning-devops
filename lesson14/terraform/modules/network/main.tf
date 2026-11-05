locals {
  public  = { for i, az in var.azs : az => cidrsubnet(var.cidr, 8, i + 1) }  # 10.0.1.0/24, 10.0.2.0/24
  private = { for i, az in var.azs : az => cidrsubnet(var.cidr, 8, i + 11) } # 10.0.11.0/24, 10.0.12.0/24
}

resource "aws_vpc" "main" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # RDS and internal ALB names resolve to private IPs inside the VPC
  tags                 = { Name = var.name }
}

# Every VPC gets a default security group that allows all traffic between its members.
# Nothing here uses it; managing it with no rules removes that open default.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name}-default-deny" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = var.name }
}

resource "aws_subnet" "public" {
  for_each                = local.public
  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each                = local.private
  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name}-private-${each.key}" }
}

# One NAT is cheaper; one per AZ keeps private egress alive when an AZ fails.
resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.azs)
  domain = "vpc"
  tags   = { Name = "${var.name}-nat-${var.azs[count.index]}" }
}

resource "aws_nat_gateway" "this" {
  count         = var.single_nat_gateway ? 1 : length(var.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[var.azs[count.index]].id
  tags          = { Name = "${var.name}-${var.azs[count.index]}" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.name}-public" }
}

# One table per AZ, so switching single_nat_gateway only changes the route target.
resource "aws_route_table" "private" {
  for_each = local.private
  vpc_id   = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : index(var.azs, each.key)].id
  }
  tags = { Name = "${var.name}-private-${each.key}" }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
