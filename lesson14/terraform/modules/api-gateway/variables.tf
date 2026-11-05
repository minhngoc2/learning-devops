variable "name" {
  description = "API and VPC Link name; also names the /aws/apigateway/<name> access-log group."
  type        = string
}

variable "vpc_link_subnet_ids" {
  description = "Private subnets for the VPC Link ENIs (at least two)."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(distinct(var.vpc_link_subnet_ids)) >= 2
    error_message = "Provide at least two distinct private subnet IDs."
  }
}

variable "vpc_link_security_group_id" {
  description = "Security group attached to the VPC Link ENIs; it must be allowed to reach the ALB on port 80."
  type        = string
}

variable "listener_arn" {
  description = "Internal ALB listener ARN that both integrations proxy to."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:.+:listener/app/", var.listener_arn))
    error_message = "listener_arn must be an Application Load Balancer listener ARN."
  }
}

variable "jwt_issuer" {
  description = "JWT issuer URL, e.g. the Cognito module's issuer output."
  type        = string

  validation {
    condition     = startswith(var.jwt_issuer, "https://")
    error_message = "jwt_issuer must be an https:// URL."
  }
}

variable "jwt_audience" {
  description = "Accepted JWT audiences (Cognito app client IDs)."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.jwt_audience) > 0
    error_message = "jwt_audience must list at least one client ID."
  }
}

variable "public_routes" {
  description = "Route keys in \"METHOD /path\" form served without auth; identity headers are stripped."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for r in var.public_routes : can(regex("^(ANY|GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) /", r))])
    error_message = "public_routes must be route keys like \"GET /api/products\"."
  }
}

variable "protected_routes" {
  description = "Route keys in \"METHOD /path\" form that require a valid JWT; identity headers are set from its claims."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for r in var.protected_routes : can(regex("^(ANY|GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) /", r))])
    error_message = "protected_routes must be route keys like \"GET /api/users/me\"."
  }
}

variable "throttling_burst_limit" {
  description = "Maximum concurrent request burst for the stage."
  type        = number
  default     = 100
  nullable    = false

  validation {
    condition     = var.throttling_burst_limit >= 0
    error_message = "throttling_burst_limit must be 0 or more."
  }
}

variable "throttling_rate_limit" {
  description = "Steady-state requests per second for the stage."
  type        = number
  default     = 50
  nullable    = false

  validation {
    condition     = var.throttling_rate_limit >= 0
    error_message = "throttling_rate_limit must be 0 or more."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for API access logs."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts: 0 (never expire) or e.g. 1, 3, 5, 7, 14, 30, 90, 365."
  }
}
