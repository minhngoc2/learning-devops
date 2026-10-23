variable "name" {
  description = "Repository name: lowercase letters, digits and . _ - / separators (ECR naming rule)."
  type        = string

  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 256 && can(regex("^[a-z0-9]+([._/-][a-z0-9]+)*$", var.name))
    error_message = "name must be 2–256 lowercase letters/digits, separated by single . _ - or /."
  }
}

variable "force_delete" {
  description = "Allow terraform destroy to delete the repository while it still holds images."
  type        = bool
  default     = false
}
