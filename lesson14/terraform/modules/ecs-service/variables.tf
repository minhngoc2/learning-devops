variable "name" {
  description = "Service, task family, security group and IAM role prefix (<name>-execution, <name>-task); log group /ecs/<name>."
  type        = string

  validation {
    # IAM role names max out at 64 characters; "-execution" uses 10 of them.
    condition     = can(regex("^[A-Za-z0-9_-]{1,54}$", var.name))
    error_message = "name must be 1–54 letters, digits, hyphens or underscores."
  }
}

variable "aws_region" {
  description = "Region for the awslogs driver (passed in: a data source here would be deferred under the caller's depends_on)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-southeast-1."
  }
}

variable "cluster_id" {
  description = "ECS cluster ID (ecs-cluster cluster_id) the service runs in."
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name, for the Application Auto Scaling resource ID service/<cluster>/<service>."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the task security group."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets where tasks run (no public IP)."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "Provide at least one subnet ID."
  }
}

variable "image" {
  description = "Full image reference, e.g. <account>.dkr.ecr.<region>.amazonaws.com/lesson14/user:v1 (ARM64)."
  type        = string
}

variable "container_port" {
  description = "Port the app listens on (1–65535); also the target-group and ingress port."
  type        = number
  default     = 8080
  nullable    = false

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be a whole number between 1 and 65535."
  }
}

variable "cpu" {
  description = "Task CPU units: 256, 512, 1024, 2048, 4096, 8192 or 16384 (256 = 0.25 vCPU)."
  type        = number
  default     = 256
  nullable    = false

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu must be a Fargate CPU size: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "memory" {
  description = "Task memory in MiB; a Fargate memory size that is valid for the chosen cpu (checked when the task definition is planned)."
  type        = number
  default     = 512
  nullable    = false

  validation {
    condition     = contains(distinct(concat([512, 1024, 2048], range(3072, 30721, 1024), range(32768, 61441, 4096), range(65536, 122881, 8192))), var.memory)
    error_message = "memory is not a Fargate memory size (512, 1024, 2048, then 1 GiB steps up to 30720, etc.)."
  }
}

variable "create_service" {
  description = "Create the ECS service and its autoscaling; false = task definition only (one-off tasks such as db-init)."
  type        = bool
  default     = true
  nullable    = false
}

variable "desired_count" {
  description = "Initial task count; afterwards autoscaling owns it (changes are ignored)."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.desired_count >= 0 && floor(var.desired_count) == var.desired_count
    error_message = "desired_count must be a whole number of 0 or more."
  }
}

variable "min_count" {
  description = "Autoscaling minimum task count."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.min_count >= 0 && floor(var.min_count) == var.min_count
    error_message = "min_count must be a whole number of 0 or more."
  }
}

variable "max_count" {
  description = "Autoscaling maximum task count; at least min_count."
  type        = number
  default     = 4
  nullable    = false

  validation {
    condition     = var.max_count >= var.min_count && var.max_count >= 1 && floor(var.max_count) == var.max_count
    error_message = "max_count must be a whole number of at least 1 and at least min_count."
  }
}

variable "cpu_target" {
  description = "Average service CPU utilization (%) that target tracking keeps."
  type        = number
  default     = 60
  nullable    = false

  validation {
    condition     = var.cpu_target > 0 && var.cpu_target <= 100
    error_message = "cpu_target must be greater than 0 and at most 100."
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

  validation {
    condition     = alltrue([for v in values(var.secrets) : can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:", v))])
    error_message = "Each secrets value must be a Secrets Manager secret ARN (optionally with a :json-key:: suffix)."
  }
}

variable "task_policy_json" {
  description = "IAM policy JSON for what the app itself may call (SQS, SNS, DynamoDB, S3...); null = no permissions."
  type        = string
  default     = null

  validation {
    condition     = var.task_policy_json == null || can(jsondecode(var.task_policy_json))
    error_message = "task_policy_json must be valid JSON or null."
  }
}

variable "ingress_security_group_ids" {
  description = "Static key => security group allowed in on container_port (e.g. { alb = <ALB SG> }); {} = no ingress (workers, one-off tasks). Keys must be known at plan time; IDs may be unknown."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "target_group_arn" {
  description = "Target group to register container app:<container_port> with; null = no load balancer (worker)."
  type        = string
  default     = null
}

variable "health_check_command" {
  description = "Container health-check command (the Go binary's -healthcheck flag by default)."
  type        = list(string)
  default     = ["CMD", "/app", "-healthcheck"]
  nullable    = false

  validation {
    condition     = length(var.health_check_command) >= 2 && contains(["CMD", "CMD-SHELL"], var.health_check_command[0])
    error_message = "health_check_command must start with CMD or CMD-SHELL followed by the command."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention; must be a value CloudWatch Logs accepts."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts: 0 (never expire) or e.g. 1, 3, 5, 7, 14, 30, 90, 365."
  }
}

variable "wait_for_steady_state" {
  description = "Make apply wait until the service is stable, so a deployment the circuit breaker fails also fails the apply."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_execute_command" {
  description = "Enable ECS Exec (aws ecs execute-command) on the service and grant the task role the SSM channel permissions."
  type        = bool
  default     = false
  nullable    = false
}
