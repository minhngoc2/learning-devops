output "security_group_id" {
  description = "ALB security group, the only source allowed into staging tasks."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "IP-type target group for ECS registration and release checks; available only once the listener exists."
  value       = aws_lb_target_group.api.arn

  # ECS rejects a target group that no listener uses yet. Waiting here (rather than a module-level
  # depends_on in the caller) keeps the ECS module's data sources readable at plan time.
  depends_on = [aws_lb_listener.http]
}

output "api_url" {
  description = "HTTP base URL; stable across ECS releases for this ALB's lifetime."
  value       = "http://${aws_lb.api.dns_name}"
}
