output "ops_topic_arn" {
  description = "Ops SNS topic ARN (in aws_region) that every alarm of this module notifies."
  value       = aws_sns_topic.ops.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name."
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}

output "dashboard_url" {
  description = "Console URL of the dashboard."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.this.dashboard_name}"
}
