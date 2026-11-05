variable "name" {
  description = "ALB name and target-group prefix; target groups are <name>-<service>, so keep it at most 24 characters (e.g. l14-dev)."
  type        = string

  validation {
    condition     = length(var.name) <= 24 && can(regex("^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$", var.name)) && !startswith(var.name, "internal-")
    error_message = "Use at most 24 alphanumeric/hyphen characters, no edge hyphens or internal- prefix (target groups add -<service>, max 32)."
  }
}

variable "vpc_id" {
  description = "VPC containing the ALB and ECS targets."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 VPC CIDR: the only source allowed on port 80 (VPC Link ENIs) and the only target-port egress destination."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be an IPv4 CIDR."
  }
}

variable "subnet_ids" {
  description = "Private subnets in at least two different availability zones."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "Provide at least two distinct private subnet IDs in different AZs."
  }
}

variable "container_port" {
  description = "ECS target and health-check port (1–65535)."
  type        = number
  default     = 8080
  nullable    = false

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be a whole number between 1 and 65535."
  }
}

variable "health_check_path" {
  description = "Target-group health-check path; must return 200."
  type        = string
  default     = "/health"
  nullable    = false

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}

variable "origin_verify_secret" {
  description = "Value CloudFront injects as X-Origin-Verify; rules forward only requests carrying it, everything else gets 403."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.origin_verify_secret) >= 16
    error_message = "origin_verify_secret must be at least 16 characters."
  }
}

variable "services" {
  description = "Path-routed services, e.g. { user = { path_pattern = \"/api/users*\", priority = 10 } }. Keys name the target groups."
  type = map(object({
    path_pattern = string
    priority     = number
  }))
  nullable = false

  validation {
    condition = length(var.services) > 0 && alltrue([
      for k, s in var.services : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", k)) && startswith(s.path_pattern, "/") && s.priority >= 1 && s.priority <= 50000 && floor(s.priority) == s.priority
    ])
    error_message = "services must be non-empty; keys lowercase alphanumeric/hyphen, path_pattern starting with /, priority a whole number 1–50000."
  }
  validation {
    condition     = length(distinct([for s in values(var.services) : s.priority])) == length(var.services)
    error_message = "Each service needs a unique listener-rule priority."
  }
}
