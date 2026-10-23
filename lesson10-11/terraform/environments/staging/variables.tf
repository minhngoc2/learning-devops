variable "aws_region" {
  description = "AWS deployment region; configure the backend region separately."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Resource prefix; keep project-staging within the ALB's 32-character name limit."
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
  description = "Staging IPv4 /16, separate from dev for future connectivity."
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && endswith(var.vpc_cidr, "/16")
    error_message = "Use an IPv4 /16; the network module carves /24 subnets."
  }
}

variable "image_tag" {
  description = "Immutable staging ECR tag to deploy; push it before the full apply."
  type        = string
  default     = "v1"
}

variable "allowed_cidr" {
  description = "Your public IPv4 /32 allowed to call the unauthenticated HTTP ALB. No public default."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.allowed_cidr))
    error_message = "allowed_cidr must be a valid IPv4 CIDR."
  }
}

variable "db_deletion_protection" {
  description = "Keep true except for a deliberate, reviewed staging teardown."
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "Optional unique RDS final snapshot name for teardown; null uses <project>-staging-final."
  type        = string
  default     = null
}
