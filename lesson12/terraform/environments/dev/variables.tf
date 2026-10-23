variable "aws_region" {
  description = "AWS region for the S3 bucket. CloudFront is global."
  type        = string
  default     = "ap-southeast-1"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-southeast-1, us-gov-west-1 or cn-north-1."
  }
}

variable "project" {
  description = "Lowercase resource prefix; names become <project>-dev-<account-id>."
  type        = string
  default     = "lesson12"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}[a-z0-9]$", var.project))
    error_message = "project must be 3–31 lowercase letters, digits or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "force_destroy" {
  description = "Delete uploaded files during destroy; enable only for a disposable lab"
  type        = bool
  default     = false
  nullable    = false
}
