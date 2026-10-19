variable "name" {
  description = "Unique name for CloudFront resources."
  type        = string
}

variable "bucket_regional_domain_name" {
  description = "S3 REST endpoint, not an S3 website endpoint."
  type        = string
}

variable "min_ttl" {
  description = "Minimum cache lifetime in seconds. Values above zero can override origin no-cache, no-store, and private directives."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.min_ttl >= 0 && floor(var.min_ttl) == var.min_ttl
    error_message = "min_ttl must be a non-negative whole number of seconds."
  }
}

variable "default_ttl" {
  description = "Cache lifetime in seconds when the origin provides no freshness headers."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.default_ttl >= var.min_ttl && floor(var.default_ttl) == var.default_ttl
    error_message = "default_ttl must be a whole number of seconds greater than or equal to min_ttl."
  }
}

variable "max_ttl" {
  description = "Maximum cache lifetime in seconds, including objects with origin freshness headers."
  type        = number
  default     = 31536000
  nullable    = false

  validation {
    condition     = var.max_ttl >= var.default_ttl && floor(var.max_ttl) == var.max_ttl
    error_message = "max_ttl must be a whole number of seconds greater than or equal to default_ttl."
  }
}
