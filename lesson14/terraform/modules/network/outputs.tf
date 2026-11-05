output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC IPv4 CIDR block, e.g. for security group rules that allow traffic from inside the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs in AZ order (route to the IGW)."
  value       = [for az in var.azs : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs in AZ order (egress through NAT)."
  value       = [for az in var.azs : aws_subnet.private[az].id]
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs in AZ order; one element when single_nat_gateway is true."
  value       = aws_nat_gateway.this[*].id
}
