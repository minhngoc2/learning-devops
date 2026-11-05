output "api_id" {
  description = "HTTP API ID."
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Base HTTPS URL of the $default stage, https://<id>.execute-api.<region>.amazonaws.com."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_host" {
  description = "api_endpoint without the https:// scheme, for a CloudFront origin domain_name."
  value       = trimprefix(aws_apigatewayv2_api.this.api_endpoint, "https://")
}

output "execution_arn" {
  description = "Execution ARN, for IAM and permission source_arn conditions."
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "access_log_group_name" {
  description = "CloudWatch log group receiving API access logs."
  value       = aws_cloudwatch_log_group.access.name
}
