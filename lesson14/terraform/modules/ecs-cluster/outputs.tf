output "cluster_id" {
  description = "ECS cluster ID, for aws_ecs_service.cluster."
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ECS cluster ARN, e.g. for IAM conditions and EventBridge targets."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "ECS cluster name, for CloudWatch dimensions and Application Auto Scaling resource IDs."
  value       = aws_ecs_cluster.this.name
}
