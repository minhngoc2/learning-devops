variable "bucket_name" {
  description = "Globally unique bucket name: 3–63 lowercase letters, digits or hyphens."
  type        = string
  nullable    = false

  validation {
    # Dots are allowed by S3 but break HTTPS certificate matching on virtual-hosted endpoints.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3–63 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
}

variable "force_destroy" {
  description = "Allow Terraform to delete all uploaded files when destroying this bucket."
  type        = bool
  default     = false
  nullable    = false
}
