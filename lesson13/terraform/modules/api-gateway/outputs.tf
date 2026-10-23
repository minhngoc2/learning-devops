output "api_id" {
  description = "HTTP API ID."
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Base HTTPS URL of the $default stage."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "execution_arn" {
  description = "Execution ARN used in Lambda permission source_arn."
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "access_log_group_name" {
  description = "CloudWatch log group receiving API access logs."
  value       = aws_cloudwatch_log_group.access.name
}
