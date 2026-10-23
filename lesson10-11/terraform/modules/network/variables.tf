variable "name" {
  description = "Name prefix for network resources."
  type        = string
}

variable "cidr" {
  description = "VPC IPv4 CIDR block; must be a /16 because subnets are carved as /24s (public x.x.1-10.0, private x.x.11-20.0)."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.cidr)) && endswith(var.cidr, "/16") && try(cidrsubnet(var.cidr, 0, 0) == var.cidr, false)
    error_message = "cidr must be an IPv4 /16 network address (no host bits), e.g. 10.0.0.0/16."
  }
}

variable "azs" {
  description = "Availability zones; one public and one private subnet per AZ. RDS needs at least two."
  type        = list(string)

  validation {
    # Public subnets use /24 indexes 1..n and private 11..n+10, so more than 10 AZs would overlap.
    condition     = length(distinct(var.azs)) == length(var.azs) && length(var.azs) >= 2 && length(var.azs) <= 10
    error_message = "Provide 2–10 distinct AZs (RDS needs two; more than 10 would overlap the private /24 range)."
  }
  nullable = false
}
