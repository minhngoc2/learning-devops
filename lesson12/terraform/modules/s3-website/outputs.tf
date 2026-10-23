output "bucket_name" {
  description = "Bucket to upload the generated site (nuxt-app/.output/public/) into."
  value       = aws_s3_bucket.website.id
}

output "bucket_arn" {
  description = "Bucket ARN for the CloudFront read policy."
  value       = aws_s3_bucket.website.arn
}

output "bucket_regional_domain_name" {
  description = "Private S3 REST origin hostname."
  value       = aws_s3_bucket.website.bucket_regional_domain_name
}
