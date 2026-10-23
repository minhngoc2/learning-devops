variable "name" {
  description = "Name for the cluster, service, task family, log group and IAM role (<name>-execution)."
  type        = string

  validation {
    # IAM role names max out at 64 characters; "-execution" uses 10 of them.
    condition     = can(regex("^[A-Za-z0-9_-]{1,54}$", var.name))
    error_message = "name must be 1–54 letters, digits, hyphens or underscores."
  }
}

variable "vpc_id" {
  description = "VPC for the task security group."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets where tasks run."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "Provide at least one subnet ID."
  }
  nullable = false
}

variable "assign_public_ip" {
  description = "Give each task a public IP. Required in public subnets without a NAT gateway (to pull images)."
  type        = bool
  default     = false
}

variable "allowed_cidr" {
  description = "IPv4 CIDR allowed to reach the container directly; required when load_balancer is null, ignored otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.allowed_cidr == null || can(cidrnetmask(var.allowed_cidr))
    error_message = "allowed_cidr must be a valid IPv4 CIDR block."
  }
}

variable "load_balancer" {
  description = "Optional ALB integration. The caller must create its listener before this service."
  type = object({
    target_group_arn  = string
    security_group_id = string
  })
  default = null
}

variable "image" {
  description = "Full image reference, e.g. <account>.dkr.ecr.<region>.amazonaws.com/repo:v1."
  type        = string
}

variable "container_port" {
  description = "Port the app listens on (1–65535)."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be a whole number between 1 and 65535."
  }
}

variable "cpu" {
  description = "Task CPU units: 256, 512, 1024, 2048, 4096, 8192 or 16384 (256 = 0.25 vCPU)."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu must be a Fargate CPU size: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "memory" {
  description = "Task memory in MiB; must be a Fargate-supported value for the chosen cpu."
  type        = number
  default     = 512

  validation {
    # Fargate CPU/memory combinations: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html#fargate-tasks-size
    condition = contains(lookup({
      "256"   = [512, 1024, 2048]
      "512"   = range(1024, 4097, 1024)
      "1024"  = range(2048, 8193, 1024)
      "2048"  = range(4096, 16385, 1024)
      "4096"  = range(8192, 30721, 1024)
      "8192"  = range(16384, 61441, 4096)
      "16384" = range(32768, 122881, 8192)
    }, tostring(var.cpu), []), var.memory)
    error_message = "memory is not a valid Fargate size for this cpu (e.g. cpu 256 allows 512, 1024 or 2048)."
  }
}

variable "desired_count" {
  description = "Number of tasks (0 stops the service without deleting it)."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 0 && floor(var.desired_count) == var.desired_count
    error_message = "desired_count must be a whole number of 0 or more."
  }
}

variable "environment" {
  description = "Plain environment variables for the container."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "secrets" {
  description = "Env var name => Secrets Manager valueFrom (ARN, optionally with :json-key:: suffix)."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention; must be a value CloudWatch Logs accepts."
  type        = number
  default     = 7

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts: 0 (never expire) or e.g. 1, 3, 5, 7, 14, 30, 90, 365."
  }
}
