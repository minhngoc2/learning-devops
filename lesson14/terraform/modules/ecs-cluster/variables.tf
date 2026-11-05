variable "name" {
  description = "ECS cluster name, e.g. lesson14-dev."
  type        = string
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights (per-task CPU/memory metrics; billed as custom metrics)."
  type        = bool
  default     = true
  nullable    = false
}
