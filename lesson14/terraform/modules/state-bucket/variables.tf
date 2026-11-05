variable "bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state, e.g. <project>-tfstate-<account-id>-<region>."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3–63 lowercase letters, digits, dots or hyphens, starting and ending with a letter or digit."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Days to keep old state versions before they expire (rollback window)."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must be a whole number of days, 1 or more."
  }
}
