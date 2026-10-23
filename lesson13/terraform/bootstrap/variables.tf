variable "aws_region" {
  description = "AWS region for the state bucket; dev.backend.hcl must use the same region."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Prefix for the bucket name <project>-tfstate-<account-id>-<region> (S3 names max 63 characters)."
  type        = string
  default     = "lesson13"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,25}[a-z0-9]$", var.project))
    error_message = "project must be 3–27 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
}
