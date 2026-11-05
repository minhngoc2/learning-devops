output "distribution_id" {
  description = "Distribution ID, for cache invalidations."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "Distribution ARN."
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  description = "Distribution hostname (dxxxx.cloudfront.net): the public entry point and PUBLIC_BASE_URL host."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "storefront_bucket_name" {
  description = "Bucket for the generated storefront (upload .output/public/)."
  value       = aws_s3_bucket.this["storefront"].bucket
}

output "images_bucket_name" {
  description = "Bucket for product images, Product Service IMAGES_BUCKET."
  value       = aws_s3_bucket.this["images"].bucket
}

output "images_bucket_arn" {
  description = "Images bucket ARN, for the Product Service task policy."
  value       = aws_s3_bucket.this["images"].arn
}
