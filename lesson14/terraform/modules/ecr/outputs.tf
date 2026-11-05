output "repository_urls" {
  description = "Registry URL per repository name, to tag and push images to."
  value       = { for name, r in aws_ecr_repository.this : name => r.repository_url }
}
