variable "aws_region" {
  description = "AWS deployment region."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Project name, used as a resource name prefix and tag."
  type        = string
  default     = "lesson10-11"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "image_tag" {
  description = "Tag of the image in ECR to deploy (push it before the full apply)."
  type        = string
  default     = "v1"
}

variable "allowed_cidr" {
  description = "Who may call the API on port 8080. Narrow to <your-ip>/32 if you don't need it public."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.allowed_cidr, 0))
    error_message = "allowed_cidr must be a valid IPv4 CIDR block."
  }
}
