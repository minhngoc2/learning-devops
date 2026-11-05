output "distribution_id" {
  description = "Distribution ID, for cache invalidations."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "Distribution ARN."
  value       = aws_cloudfront_distribution.this.arn
}

output "web_acl_id" {
  description = "WAF web ACL ARN attached to the distribution; null without WAF."
  value       = aws_cloudfront_distribution.this.web_acl_id
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

output "bucket_public_access_blocks" {
  description = "Bucket role (storefront, images) => its four public-access-block flags, for callers' tests and audits."
  value = {
    for k, b in aws_s3_bucket_public_access_block.this : k => {
      block_public_acls       = b.block_public_acls
      block_public_policy     = b.block_public_policy
      ignore_public_acls      = b.ignore_public_acls
      restrict_public_buckets = b.restrict_public_buckets
    }
  }
}
