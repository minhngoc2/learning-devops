output "table_name" {
  description = "Table name, e.g. for the TABLE_NAME environment variable."
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "Table ARN, for least-privilege IAM policies."
  value       = aws_dynamodb_table.this.arn
}
