output "cloudfront_url" {
  description = "Public entry point: storefront at /, API at /api/*, product images at /images/*."
  value       = "https://${module.edge.domain_name}"
}

output "api_endpoint" {
  description = "Raw API Gateway URL, for diagnostics only: returns 403 without X-Origin-Verify; use cloudfront_url."
  value       = module.api.api_endpoint
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID, for aws cognito-idp admin-* commands."
  value       = module.cognito.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito app client ID (the JWT audience)."
  value       = module.cognito.client_id
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = module.cluster.cluster_name
}

output "service_names" {
  description = "Service key → ECS service name, for aws ecs update-service and logs."
  value       = { for k, s in module.service : k => s.service_name }
}

output "ecr_repository_urls" {
  description = "Image name (service or db-init) → ECR repository URL to tag and push <url>:<image_tag>."
  value       = { for s in local.all_task_names : s => module.ecr.repository_urls["${var.project}/${s}"] }
}

output "db_init_run_command" {
  description = "AWS CLI command that runs the one-off db-init task (schemas, roles, grants) in the private subnets."
  value = join(" ", [
    "aws ecs run-task",
    "--cluster ${module.cluster.cluster_name}",
    "--launch-type FARGATE",
    "--task-definition ${module.db_init.task_definition_arn}",
    "--network-configuration \"awsvpcConfiguration={subnets=[${join(",", module.network.private_subnet_ids)}],securityGroups=[${module.db_init.security_group_id}],assignPublicIp=DISABLED}\"",
    "--region ${var.aws_region}",
  ])
}

output "db_init_log_group_name" {
  description = "CloudWatch log group of the db-init task, read by scripts/run-db-init.sh."
  value       = module.db_init.log_group_name
}

output "dashboard_url" {
  description = "CloudWatch dashboard console URL."
  value       = module.observability.dashboard_url
}

output "images_bucket_name" {
  description = "Product images bucket; upload seed images under products/."
  value       = module.edge.images_bucket_name
}

output "storefront_bucket_name" {
  description = "Storefront bucket; sync the generated site (.output/public/) here."
  value       = module.edge.storefront_bucket_name
}

output "alb_dns_name" {
  description = "Internal ALB DNS name (resolvable only inside the VPC)."
  value       = module.alb.dns_name
}

output "ops_topic_arn" {
  description = "Ops SNS topic (aws_region) that the regional alarms notify; the WAF alarm uses waf_ops_topic_arn in us-east-1."
  value       = module.observability.ops_topic_arn
}

output "waf_ops_topic_arn" {
  description = "us-east-1 SNS topic that the WAF BlockedRequests alarm notifies."
  value       = module.waf.ops_topic_arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID, for cache invalidations after a storefront upload."
  value       = module.edge.distribution_id
}

output "aws_region" {
  description = "Region for AWS CLI commands."
  value       = var.aws_region
}
