variable "aws_region" {
  description = "AWS region for the S3 bucket. CloudFront is global."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Lowercase resource prefix: account ID and environment are appended."
  type        = string
  default     = "lesson12"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}[a-z0-9]$", var.project))
    error_message = "project must be 3–31 lowercase letters, digits or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "environment" {
  description = "Environment name, also included in resource names and tags"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "force_destroy" {
  description = "Delete uploaded files during destroy; enable only for a disposable lab"
  type        = bool
  default     = false
}
