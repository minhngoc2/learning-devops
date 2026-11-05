variable "name" {
  description = "Name prefix for the buckets (<name>-storefront-<account id>, <name>-images-<account id>), OAC, function and distribution comment."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3–32 lowercase letters, digits or hyphens, starting and ending with a letter or digit (S3 bucket name rule, leaving room for suffixes)."
  }
}

variable "api_host" {
  description = "API Gateway hostname without scheme or path (api-gateway module's api_host output); origin for /api/*."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.api_host))
    error_message = "api_host must be a bare hostname such as abc123.execute-api.ap-southeast-1.amazonaws.com (no https:// or path)."
  }
}

variable "origin_verify_secret" {
  description = "Value CloudFront sends as X-Origin-Verify to the API origin; the ALB only routes requests carrying it."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.origin_verify_secret) >= 16
    error_message = "origin_verify_secret must be at least 16 characters."
  }
}

variable "web_acl_arn" {
  description = "WAFv2 web ACL ARN (scope CLOUDFRONT, us-east-1) to attach; null = no WAF."
  type        = string
  default     = null

  validation {
    condition     = var.web_acl_arn == null || can(regex("^arn:aws[a-z-]*:wafv2:us-east-1:[0-9]{12}:global/webacl/", var.web_acl_arn))
    error_message = "web_acl_arn must be a global (CLOUDFRONT scope) WAFv2 web ACL ARN in us-east-1, or null."
  }
}

variable "force_destroy" {
  description = "Let destroy delete the buckets while they still hold objects (dev sets true)."
  type        = bool
  default     = false
  nullable    = false
}

variable "price_class" {
  description = "CloudFront price class: which edge locations serve the distribution."
  type        = string
  default     = "PriceClass_200"
  nullable    = false

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}
