variable "bucket_name" {
  description = "Globally unique bucket name."
  type        = string
}

variable "force_destroy" {
  description = "Allow Terraform to delete all uploaded files when destroying this bucket."
  type        = bool
  default     = false
}
