variable "name" {
  description = "Prefix for the ops topic (<name>-ops), alarm names and the dashboard name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,200}$", var.name))
    error_message = "name must be 1–200 letters, digits, hyphens or underscores (SNS topic and dashboard name rules)."
  }
}

variable "aws_region" {
  description = "Region of the regional resources (ALB, ECS, RDS, SQS, API Gateway); CloudFront and WAF widgets always read us-east-1."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-southeast-1."
  }
}

variable "alb_arn_suffix" {
  description = "Internal ALB ARN suffix (alb-internal alb_arn_suffix), the LoadBalancer dimension."
  type        = string
}

variable "target_group_arn_suffixes" {
  description = "Service → target group ARN suffix (alb-internal target_group_arn_suffixes), for per-service ALB widgets."
  type        = map(string)
  nullable    = false
}

variable "cluster_name" {
  description = "ECS cluster name, the ClusterName dimension (Container Insights must be enabled)."
  type        = string
}

variable "service_names" {
  description = "Service key → ECS service name; one under-desired alarm and dashboard series per entry."
  type        = map(string)
  nullable    = false
}

variable "desired_counts" {
  description = "Service key → desired task count; the alarm fires when RunningTaskCount averages below it. Keys must match service_names."
  type        = map(number)
  nullable    = false

  validation {
    condition     = toset(keys(var.desired_counts)) == toset(keys(var.service_names))
    error_message = "desired_counts must have exactly the same keys as service_names."
  }
  validation {
    condition     = alltrue([for c in values(var.desired_counts) : c >= 0 && floor(c) == c])
    error_message = "Every desired count must be a whole number of 0 or more."
  }
}

variable "db_identifier" {
  description = "RDS instance identifier, the DBInstanceIdentifier dimension."
  type        = string
}

variable "db_max_connections" {
  description = "The instance's max_connections; the connections alarm fires above 80 % of it."
  type        = number

  validation {
    condition     = var.db_max_connections >= 1 && floor(var.db_max_connections) == var.db_max_connections
    error_message = "db_max_connections must be a whole number of at least 1."
  }
}

variable "dlq_names" {
  description = "Consumer → DLQ name (messaging dlq_names); one not-empty alarm per entry."
  type        = map(string)
  nullable    = false
}

variable "api_id" {
  description = "API Gateway HTTP API ID, the ApiId dimension."
  type        = string
}

variable "web_acl_name" {
  description = "WAF web ACL name (waf web_acl_name), for the us-east-1 BlockedRequests widget."
  type        = string
}

variable "distribution_id" {
  description = "CloudFront distribution ID, for the us-east-1 edge widgets."
  type        = string
}

variable "alarm_email" {
  description = "Email subscribed to the ops topic (confirm the email AWS sends); null = no subscription."
  type        = string
  default     = null

  validation {
    condition     = var.alarm_email == null || can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.alarm_email))
    error_message = "alarm_email must be an email address or null."
  }
}
