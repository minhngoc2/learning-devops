output "address" {
  description = "DB hostname (resolves to a private IP)."
  value       = aws_db_instance.main.address
}

output "port" {
  description = "DB port."
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Database name."
  value       = aws_db_instance.main.db_name
}

output "username" {
  description = "Master username."
  value       = aws_db_instance.main.username
}

output "secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master credentials (JSON: username, password)."
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "DB security group; add ingress rules from callers."
  value       = aws_security_group.db.id
}
