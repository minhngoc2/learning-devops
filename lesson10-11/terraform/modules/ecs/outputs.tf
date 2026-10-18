output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.api.name
}

output "security_group_id" {
  description = "Task security group (use as the source for DB ingress)."
  value       = aws_security_group.api.id
}
