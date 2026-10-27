variable "name" {
  description = "Table name, unique per account and region."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]{3,255}$", var.name))
    error_message = "name must be 3–255 letters, digits, underscores, hyphens or dots."
  }
}

variable "hash_key" {
  description = "Partition key attribute name, e.g. id."
  type        = string
}

variable "hash_key_type" {
  description = "Partition key type: S (string), N (number) or B (binary)."
  type        = string
  default     = "S"

  validation {
    condition     = contains(["S", "N", "B"], var.hash_key_type)
    error_message = "hash_key_type must be S, N or B."
  }
}

variable "range_key" {
  description = "Optional sort key attribute name; null = partition key only."
  type        = string
  default     = null
}

variable "range_key_type" {
  description = "Sort key type: S, N or B. Ignored without range_key."
  type        = string
  default     = "S"

  validation {
    condition     = contains(["S", "N", "B"], var.range_key_type)
    error_message = "range_key_type must be S, N or B."
  }
}

variable "point_in_time_recovery" {
  description = "Enable continuous backups (point-in-time restore for 35 days)."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Block DeleteTable, including terraform destroy. Turn on for any table whose data matters."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Customer managed KMS key ARN for encryption at rest; null = the AWS managed key aws/dynamodb."
  type        = string
  default     = null
}
