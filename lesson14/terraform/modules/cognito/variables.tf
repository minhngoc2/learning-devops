variable "name" {
  description = "User pool name; the app client is <name>-web."
  type        = string
}

variable "password_minimum_length" {
  description = "Minimum password length (8–99); passwords also need upper, lower, number and symbol."
  type        = number
  default     = 8
  nullable    = false

  validation {
    condition     = var.password_minimum_length >= 8 && var.password_minimum_length <= 99 && floor(var.password_minimum_length) == var.password_minimum_length
    error_message = "password_minimum_length must be a whole number between 8 and 99."
  }
}
