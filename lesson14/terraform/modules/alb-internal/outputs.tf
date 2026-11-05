output "alb_arn" {
  description = "Internal ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix, the LoadBalancer dimension for CloudWatch alarms."
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  description = "Internal ALB DNS name (resolvable only inside the VPC)."
  value       = aws_lb.this.dns_name
}

output "listener_arn" {
  description = "HTTP :80 listener ARN, the API Gateway VPC Link integration_uri."
  value       = aws_lb_listener.http.arn
}

output "security_group_id" {
  description = "ALB security group; ECS services allow it on the container port."
  value       = aws_security_group.alb.id
}

output "target_group_arns" {
  description = "Map service → target group ARN for ECS load_balancer blocks; available only once the listener rules exist."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }

  # ECS rejects a target group that no listener uses yet.
  depends_on = [aws_lb_listener_rule.this]
}

output "target_group_arn_suffixes" {
  description = "Map service → target group ARN suffix, the TargetGroup dimension for CloudWatch alarms."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn_suffix }
}
