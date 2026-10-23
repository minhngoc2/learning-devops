output "function_name" {
  description = "Function name, e.g. for aws lambda invoke."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "Function ARN."
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "ARN that API Gateway integrations use to invoke the function."
  value       = aws_lambda_function.this.invoke_arn
}

output "role_name" {
  description = "Execution role name; attach extra policies here."
  value       = aws_iam_role.this.name
}

output "log_group_name" {
  description = "CloudWatch log group receiving the function's output."
  value       = aws_cloudwatch_log_group.this.name
}
