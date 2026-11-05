variable "name" {
  description = "Web ACL name and metric-name prefix (<name>-<rule>)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,100}$", var.name))
    error_message = "name must be 1–100 letters, digits, hyphens or underscores (WAFv2 name rule, leaving room for rule suffixes)."
  }
}

variable "rate_limit" {
  description = "Requests per 5 minutes from one IP before the rate-based rule blocks it."
  type        = number
  default     = 2000
  nullable    = false

  validation {
    condition     = var.rate_limit >= 100 && var.rate_limit <= 2000000000 && floor(var.rate_limit) == var.rate_limit
    error_message = "rate_limit must be a whole number of at least 100 (the WAF minimum for rate-based rules)."
  }
}

variable "blocked_requests_threshold" {
  description = "Blocked requests per 5 minutes above which the alarm fires."
  type        = number
  default     = 100
  nullable    = false

  validation {
    condition     = var.blocked_requests_threshold >= 1
    error_message = "blocked_requests_threshold must be at least 1."
  }
}

variable "alarm_email" {
  description = "Email subscribed to this module's us-east-1 ops topic (confirm the email AWS sends); null = no subscription and no BlockedRequests alarm."
  type        = string
  default     = null

  validation {
    condition     = var.alarm_email == null || can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.alarm_email))
    error_message = "alarm_email must be an email address or null."
  }
}
