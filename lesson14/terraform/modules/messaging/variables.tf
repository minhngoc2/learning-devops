variable "name" {
  description = "Name prefix: topic <name>-order-events, queues <name>-<consumer>-order-events and -dlq."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,40}$", var.name))
    error_message = "name must be 1–40 letters, digits, hyphens or underscores (SNS/SQS name rule, leaving room for suffixes)."
  }
}

variable "event_types" {
  description = "Allowed values of the event_type message attribute published on the topic."
  type        = list(string)
  default     = ["OrderCreated", "PaymentSucceeded", "PaymentFailed"]
  nullable    = false

  validation {
    condition     = length(var.event_types) > 0 && length(distinct(var.event_types)) == length(var.event_types)
    error_message = "event_types must be a non-empty list without duplicates."
  }
}

variable "consumers" {
  description = "Consumer name → event types it subscribes to; each consumer gets its own queue, DLQ and filtered subscription."
  type        = map(list(string))
  nullable    = false

  validation {
    condition     = alltrue([for c in keys(var.consumers) : can(regex("^[a-z][a-z0-9-]{0,19}$", c))])
    error_message = "Consumer names must be 1–20 lowercase letters, digits or hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue([for types in values(var.consumers) : length(types) > 0 && length(setsubtract(types, var.event_types)) == 0])
    error_message = "Every consumer must subscribe to at least one event type, and only to types listed in event_types."
  }
}

variable "max_receive_count" {
  description = "Receives before a message moves to the consumer's DLQ."
  type        = number
  default     = 5
  nullable    = false

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "max_receive_count must be between 1 and 1000."
  }
}

variable "visibility_timeout_seconds" {
  description = "How long a received message stays hidden from other consumers; set above the handler's processing time."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200 (12 hours)."
  }
}

variable "message_retention_seconds" {
  description = "How long queues keep unprocessed messages (default 4 days); DLQs keep them for the 14-day maximum."
  type        = number
  default     = 345600
  nullable    = false

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600 (14 days)."
  }
}
