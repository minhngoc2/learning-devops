output "ecr_repository_url" {
  description = "Staging's separate immutable image repository."
  value       = module.ecr.repository_url
}

output "cluster_name" {
  description = "Staging ECS cluster."
  value       = module.ecs.cluster_name
}

output "service_name" {
  description = "Staging ECS service."
  value       = module.ecs.service_name
}

output "rds_endpoint" {
  description = "Staging private DB hostname; dev data is not copied here."
  value       = module.rds.address
}

output "api_url" {
  description = "Use this HTTP ALB URL across task replacements."
  value       = module.alb.api_url
}

output "target_group_arn" {
  description = "Inspect task registration and ALB health with this target group."
  value       = module.alb.target_group_arn
}
