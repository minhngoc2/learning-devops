output "topic_arn" {
  description = "Order events topic ARN, for the publisher's TOPIC_ARN and sns:Publish policy."
  value       = aws_sns_topic.this.arn
}

output "queue_urls" {
  description = "Consumer → queue URL, for the consumer's QUEUE_URL."
  value       = { for c, q in aws_sqs_queue.this : c => q.url }
}

output "queue_arns" {
  description = "Consumer → queue ARN, for sqs:ReceiveMessage/DeleteMessage policies."
  value       = { for c, q in aws_sqs_queue.this : c => q.arn }
}

output "queue_names" {
  description = "Consumer → queue name, for CloudWatch queue-age alarms."
  value       = { for c, q in aws_sqs_queue.this : c => q.name }
}

output "dlq_arns" {
  description = "Consumer → DLQ ARN, e.g. for a redrive task."
  value       = { for c, q in aws_sqs_queue.dlq : c => q.arn }
}

output "dlq_names" {
  description = "Consumer → DLQ name, for CloudWatch DLQ-depth alarms."
  value       = { for c, q in aws_sqs_queue.dlq : c => q.name }
}
