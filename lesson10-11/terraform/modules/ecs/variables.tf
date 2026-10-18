variable "name" {
  description = "Name for the cluster, service, task family, log group and IAM role."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the task security group."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets where tasks run."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Give each task a public IP. Required in public subnets without a NAT gateway (to pull images)."
  type        = bool
  default     = false
}

variable "allowed_cidr" {
  description = "IPv4 CIDR allowed to reach the container directly; required when load_balancer is null."
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
  description = "Port the app listens on."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks."
  type        = number
  default     = 1
}

variable "environment" {
  description = "Plain environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Env var name => Secrets Manager valueFrom (ARN, optionally with :json-key:: suffix)."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 7
}
