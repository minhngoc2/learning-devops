variable "aws_region" {
  description = "AWS deployment region."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Project name, used as a resource name prefix and tag."
  type        = string
  default     = "lesson10-11"
}

variable "azs" {
  description = "Standard AZs in aws_region (the network module takes 2-10), pinned so subnets never move if AWS reports a zone as impaired. Change together with aws_region."
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
  nullable    = false

  validation {
    # Region code plus one letter: rejects Local/Wavelength Zones (e.g. us-east-1-bos-1a), which RDS subnet groups cannot use.
    condition     = alltrue([for az in var.azs : can(regex("^${var.aws_region}[a-z]$", az))])
    error_message = "azs must be standard zones in aws_region, e.g. [\"ap-southeast-1a\", \"ap-southeast-1b\"]."
  }
}

variable "vpc_cidr" {
  description = "VPC IPv4 /16; the network module carves /24 subnets."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && endswith(var.vpc_cidr, "/16")
    error_message = "Use an IPv4 /16; the network module carves /24 subnets."
  }
}

variable "image_tag" {
  description = "Tag of the image in ECR to deploy (push it before the full apply)."
  type        = string
  default     = "v1"
}

variable "allowed_cidr" {
  description = "Who may call the API on port 8080. Narrow to <your-ip>/32 if you don't need it public."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrnetmask(var.allowed_cidr)) # cidrnetmask rejects IPv6, which cidr_ipv4 cannot take
    error_message = "allowed_cidr must be a valid IPv4 CIDR block."
  }
}
