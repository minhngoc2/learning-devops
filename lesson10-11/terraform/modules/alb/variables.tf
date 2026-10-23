variable "name" {
  description = "ALB and target-group name (at most 32 characters)."
  type        = string

  validation {
    condition     = length(var.name) <= 32 && can(regex("^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$", var.name)) && !startswith(var.name, "internal-")
    error_message = "Use at most 32 alphanumeric/hyphen characters, no edge hyphens or internal- prefix."
  }
}

variable "vpc_id" {
  description = "VPC containing the ALB and ECS targets."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 VPC CIDR allowed for ALB target-port egress."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be an IPv4 CIDR."
  }
}

variable "subnet_ids" {
  description = "Public subnets in at least two different availability zones."
  type        = list(string)

  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "Provide at least two distinct public subnet IDs in different AZs."
  }
  nullable = false
}

variable "allowed_cidr" {
  description = "IPv4 CIDR permitted to call HTTP port 80. Use your public IPv4 /32 for this unauthenticated lab."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.allowed_cidr))
    error_message = "allowed_cidr must be an IPv4 CIDR."
  }
}

variable "container_port" {
  description = "ECS target and health-check port (1–65535)."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be a whole number between 1 and 65535."
  }
}
