output "api_url" {
  description = "Base HTTPS URL; append /users, /users/<id> or /health."
  value       = module.api_gateway.api_endpoint
}

output "function_name" {
  description = "Lambda function name for aws lambda invoke and logs."
  value       = module.lambda_function.function_name
}

output "table_name" {
  description = "DynamoDB users table."
  value       = module.users_table.table_name
}

output "log_group_name" {
  description = "Function log group."
  value       = module.lambda_function.log_group_name
}

output "access_log_group_name" {
  description = "API Gateway access log group."
  value       = module.api_gateway.access_log_group_name
}

output "aws_region" {
  description = "Region for AWS CLI commands."
  value       = var.aws_region
}
