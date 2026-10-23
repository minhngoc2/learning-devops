variable "aws_region" {
  description = "AWS region for the function and API."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Lowercase resource prefix; names become <project>-dev."
  type        = string
  default     = "lesson13"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}[a-z0-9]$", var.project))
    error_message = "project must be 3–31 lowercase letters, digits or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "greeting" {
  description = "GREETING environment variable read by the Go app."
  type        = string
  default     = "Hello"
}
