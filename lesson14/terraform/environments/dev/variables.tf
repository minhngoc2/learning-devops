variable "aws_region" {
  description = "AWS region for everything except the CloudFront-scope WAF (always us-east-1)."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Lowercase resource prefix; names become <project>-dev."
  type        = string
  default     = "lesson14"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}[a-z0-9]$", var.project))
    error_message = "project must be 3–31 lowercase letters, digits or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "azs" {
  description = "Standard AZs in aws_region (the network module takes 2–10), pinned so subnets never move. Change together with aws_region."
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
  nullable    = false

  validation {
    # Region code plus one letter: rejects Local/Wavelength Zones, which RDS subnet groups cannot use.
    condition     = alltrue([for az in var.azs : can(regex("^${var.aws_region}[a-z]$", az))])
    error_message = "azs must be standard zones in aws_region, e.g. [\"ap-southeast-1a\", \"ap-southeast-1b\"]."
  }
}

variable "vpc_cidr" {
  description = "VPC IPv4 /16; the network module carves /24 subnets."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && endswith(var.vpc_cidr, "/16")
    error_message = "Use an IPv4 /16; the network module carves /24 subnets."
  }
}

variable "image_tag" {
  description = "Image tag deployed for every service and db-init; push it to each lesson14/<service> repository first."
  type        = string
  default     = "v1"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image_tag))
    error_message = "image_tag must be a valid Docker tag (letters, digits, _ . -, at most 128 characters)."
  }
}

variable "desired_count" {
  description = "Initial task count per service; autoscaling owns it afterwards."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 0 && floor(var.desired_count) == var.desired_count
    error_message = "desired_count must be a whole number of 0 or more."
  }
}

variable "min_count" {
  description = "Autoscaling minimum tasks per service."
  type        = number
  default     = 1

  validation {
    condition     = var.min_count >= 0 && floor(var.min_count) == var.min_count
    error_message = "min_count must be a whole number of 0 or more."
  }
}

variable "max_count" {
  description = "Autoscaling maximum tasks per service; at least min_count."
  type        = number
  default     = 4

  validation {
    condition     = var.max_count >= 1 && var.max_count >= var.min_count && floor(var.max_count) == var.max_count
    error_message = "max_count must be a whole number of at least 1 and at least min_count."
  }
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all private subnets (cheaper) instead of one per AZ."
  type        = bool
  default     = true
}

variable "multi_az" {
  description = "Run an RDS standby in a second AZ (doubles the DB cost)."
  type        = bool
  default     = false
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = startswith(var.db_instance_class, "db.")
    error_message = "db_instance_class must be an RDS class such as db.t4g.micro."
  }
}

variable "db_backup_retention_period" {
  description = "Days of automated RDS backups (0 disables them)."
  type        = number
  default     = 1

  validation {
    condition     = var.db_backup_retention_period >= 0 && var.db_backup_retention_period <= 35
    error_message = "db_backup_retention_period must be between 0 and 35."
  }
}

variable "db_deletion_protection" {
  description = "Block deletion of the RDS instance (dev: off so destroy works)."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip the final RDS snapshot on destroy (dev: on)."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Let destroy delete the S3 buckets and ECR repositories while they still hold objects or images."
  type        = bool
  default     = true
}

variable "alarm_email" {
  description = "Email subscribed to both ops topics (ap-southeast-1 alarms and the us-east-1 WAF alarm); null = no subscription."
  type        = string
  default     = null

  validation {
    condition     = var.alarm_email == null || can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.alarm_email))
    error_message = "alarm_email must be an email address or null."
  }
}

variable "notify_from_email" {
  description = "SES sender for Notification Service (verified by Terraform-created identity); null = NOTIFY_MODE=log."
  type        = string
  default     = null

  validation {
    condition     = var.notify_from_email == null || can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.notify_from_email))
    error_message = "notify_from_email must be an email address or null."
  }
}

variable "container_insights" {
  description = "Enable ECS Container Insights; the service under-desired alarms read its RunningTaskCount."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for service and API access logs."
  type        = number
  default     = 7

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts: 0 (never expire) or e.g. 1, 3, 5, 7, 14, 30, 90, 365."
  }
}
