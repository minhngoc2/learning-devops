variable "aws_region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Prefix for the bucket name."
  type        = string
  default     = "lesson10-11"
}
