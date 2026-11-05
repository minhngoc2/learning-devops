output "service_name" {
  description = "ECS service name, for CloudWatch ServiceName dimensions; null when create_service is false."
  value       = one(aws_ecs_service.this[*].name)
}

output "task_definition_arn" {
  description = "Task definition ARN, e.g. for aws ecs run-task (db-init)."
  value       = aws_ecs_task_definition.this.arn
}

output "security_group_id" {
  description = "Task security group, the source for DB ingress rules; exists even without a service."
  value       = aws_security_group.this.id
}

output "task_role_name" {
  description = "Task role name, to attach extra policies from the caller."
  value       = aws_iam_role.task.name
}

output "task_role_arn" {
  description = "Task role ARN (the app's identity)."
  value       = aws_iam_role.task.arn
}

output "execution_role_arn" {
  description = "Execution role ARN (ECS agent: image pull, logs, secrets)."
  value       = aws_iam_role.execution.arn
}

output "log_group_name" {
  description = "CloudWatch log group /ecs/<name>."
  value       = aws_cloudwatch_log_group.this.name
}

output "scalable_target_resource_id" {
  description = "Application Auto Scaling resource ID service/<cluster>/<service>, for extra scaling policies; null without a service."
  value       = one(aws_appautoscaling_target.this[*].resource_id)
}
