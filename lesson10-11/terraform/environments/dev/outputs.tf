output "ecr_repository_url" {
  description = "docker tag/push target."
  value       = module.ecr.repository_url
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs.cluster_name
}

output "service_name" {
  description = "ECS service name."
  value       = module.ecs.service_name
}

output "rds_endpoint" {
  description = "RDS hostname (private; only reachable from the API tasks)."
  value       = module.rds.address
}

# The task's public IP belongs to its ENI and changes on every new task, so Terraform cannot output it.
output "get_public_ip" {
  description = "Run this to print the running task's public IP."
  value       = <<-EOT
    TASK=$(aws ecs list-tasks --region ${var.aws_region} --cluster ${module.ecs.cluster_name} --service-name ${module.ecs.service_name} --query 'taskArns[0]' --output text)
    ENI=$(aws ecs describe-tasks --region ${var.aws_region} --cluster ${module.ecs.cluster_name} --tasks $TASK --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text)
    aws ec2 describe-network-interfaces --region ${var.aws_region} --network-interface-ids $ENI --query 'NetworkInterfaces[0].Association.PublicIp' --output text
  EOT
}
