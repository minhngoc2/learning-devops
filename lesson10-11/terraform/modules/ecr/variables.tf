variable "name" {
  description = "Repository name."
  type        = string
}

variable "force_delete" {
  description = "Allow terraform destroy to delete the repository while it still holds images."
  type        = bool
  default     = false
}
