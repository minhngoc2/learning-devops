variable "aws_region" {
  description = "AWS region for the table, function and API."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Lowercase resource prefix; names become <project>-dev."
  type        = string
  default     = "lesson12-13"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}[a-z0-9]$", var.project))
    error_message = "project must be 3–31 lowercase letters, digits or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "lambda_memory_size" {
  description = "Function memory in MB; CPU scales with it. The assignment asks for 1 GB."
  type        = number
  default     = 1024
}

variable "seed_users" {
  description = "Load the sample users in seed/users.json into the table."
  type        = bool
  default     = true
}
