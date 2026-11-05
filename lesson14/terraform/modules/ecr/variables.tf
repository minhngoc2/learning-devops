variable "names" {
  description = "Repository names, one per image: lowercase letters, digits and . _ - / separators (ECR naming rule)."
  type        = set(string)
  nullable    = false

  validation {
    condition     = alltrue([for n in var.names : length(n) >= 2 && length(n) <= 256 && can(regex("^[a-z0-9]+([._/-][a-z0-9]+)*$", n))])
    error_message = "Each name must be 2–256 lowercase letters/digits, separated by single . _ - or /."
  }
}

variable "force_delete" {
  description = "Allow terraform destroy to delete repositories while they still hold images."
  type        = bool
  default     = false
}
