variable "name" {
  description = "API name; also names the access-log group."
  type        = string
}

variable "lambda_function_name" {
  description = "Function that receives every route."
  type        = string
}

variable "lambda_invoke_arn" {
  description = "invoke_arn of that function."
  type        = string
}

variable "routes" {
  description = "Route keys in \"METHOD /path\" form, e.g. [\"GET /users/{id}\"]. Unlisted paths return 404 from API Gateway."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.routes) > 0 && alltrue([for r in var.routes : can(regex("^(ANY|GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) /", r))])
    error_message = "routes must be non-empty route keys like \"GET /hello\"."
  }
}

variable "throttling_burst_limit" {
  description = "Maximum concurrent request burst for the stage."
  type        = number
  default     = 20

  validation {
    condition     = var.throttling_burst_limit >= 0
    error_message = "throttling_burst_limit must be 0 or more."
  }
}

variable "throttling_rate_limit" {
  description = "Steady-state requests per second for the stage."
  type        = number
  default     = 10

  validation {
    condition     = var.throttling_rate_limit >= 0
    error_message = "throttling_rate_limit must be 0 or more."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for API access logs."
  type        = number
  default     = 7

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts: 0 (never expire) or e.g. 1, 3, 5, 7, 14, 30, 90, 365."
  }
}
