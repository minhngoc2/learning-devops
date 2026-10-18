output "repository_url" {
  description = "Registry URL to tag and push images to."
  value       = aws_ecr_repository.api.repository_url
}
