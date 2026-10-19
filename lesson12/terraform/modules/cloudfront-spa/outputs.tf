output "distribution_id" {
  description = "CloudFront distribution ID for cache invalidation."
  value       = aws_cloudfront_distribution.website.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN for the S3 bucket policy."
  value       = aws_cloudfront_distribution.website.arn
}

output "domain_name" {
  description = "CloudFront hostname."
  value       = aws_cloudfront_distribution.website.domain_name
}
