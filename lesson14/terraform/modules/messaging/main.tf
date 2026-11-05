resource "aws_sns_topic" "this" {
  name = "${var.name}-order-events"
}

# DLQs keep failed messages for the 14-day maximum so they can be inspected and redriven.
resource "aws_sqs_queue" "dlq" {
  for_each = var.consumers

  name                      = "${var.name}-${each.key}-order-events-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "this" {
  for_each = var.consumers

  name                       = "${var.name}-${each.key}-order-events"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = 20 # long polling: fewer empty receives
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })
}

# Only this topic may send to the queue.
resource "aws_sqs_queue_policy" "this" {
  for_each = var.consumers

  queue_url = aws_sqs_queue.this[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOrderEventsTopic"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "SQS:SendMessage"
      Resource  = aws_sqs_queue.this[each.key].arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.this.arn } }
    }]
  })
}

# Raw delivery: the queue receives the published body unchanged, with event_type as a message attribute.
resource "aws_sns_topic_subscription" "this" {
  for_each = var.consumers

  topic_arn            = aws_sns_topic.this.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.this[each.key].arn
  raw_message_delivery = true
  filter_policy        = jsonencode({ event_type = each.value })
  filter_policy_scope  = "MessageAttributes"

  depends_on = [aws_sqs_queue_policy.this]
}
