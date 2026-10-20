output "bucket_name" {
  description = "Upload the contents of nuxt-app/.output/public/ to this bucket."
  value       = module.s3_website.bucket_name
}

output "distribution_id" {
  description = "CloudFront distribution ID for invalidation."
  value       = module.cloudfront.distribution_id
}

output "website_url" {
  description = "Public HTTPS URL of the Nuxt static website."
  value       = "https://${module.cloudfront.domain_name}"
}

output "aws_region" {
  description = "Region for AWS CLI upload commands."
  value       = var.aws_region
}
