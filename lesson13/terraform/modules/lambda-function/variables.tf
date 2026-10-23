variable "function_name" {
  description = "Lambda function name; also names the IAM role (<name>-lambda) and log group."
  type        = string

  validation {
    # IAM role names max out at 64 characters; "-lambda" uses 7 of them.
    condition     = can(regex("^[A-Za-z0-9_-]{1,57}$", var.function_name))
    error_message = "function_name must be 1–57 letters, digits, hyphens or underscores."
  }
}

variable "package_path" {
  description = "Path to the deployment .zip file."
  type        = string
}

variable "runtime" {
  description = "Lambda runtime, e.g. provided.al2023 (Go/Rust), python3.13, nodejs22.x."
  type        = string
}

variable "handler" {
  description = "Entry point. For provided.* runtimes the executable is always named bootstrap."
  type        = string
}

variable "architectures" {
  description = "Instruction set; the package must be built for it."
  type        = list(string)
  default     = ["arm64"]

  validation {
    condition     = length(var.architectures) == 1 && contains(["arm64", "x86_64"], var.architectures[0])
    error_message = "architectures must be [\"arm64\"] or [\"x86_64\"]."
  }
}

variable "memory_size" {
  description = "Memory in MB (128–10240). CPU is allocated in proportion."
  type        = number
  default     = 128

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240 && floor(var.memory_size) == var.memory_size
    error_message = "memory_size must be a whole number of MB between 128 and 10240."
  }
}

variable "timeout" {
  description = "Maximum seconds per invocation (1–900). API Gateway HTTP APIs stop waiting after 30."
  type        = number
  default     = 10

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900 && floor(var.timeout) == var.timeout
    error_message = "timeout must be a whole number of seconds between 1 and 900."
  }
}

variable "environment_variables" {
  description = "Plain environment variables for the function. Do not put secrets here."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "reserved_concurrent_executions" {
  description = "Cap on simultaneous executions; -1 = no reservation (uses the account's shared pool). Reserving fails on accounts whose total limit leaves under 100 unreserved."
  type        = number
  default     = -1

  validation {
    condition     = var.reserved_concurrent_executions >= -1 && floor(var.reserved_concurrent_executions) == var.reserved_concurrent_executions
    error_message = "reserved_concurrent_executions must be -1 or a whole number >= 0."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the function's log group."
  type        = number
  default     = 7

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts: 0 (never expire) or e.g. 1, 3, 5, 7, 14, 30, 90, 365."
  }
}
