mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

run "private_bucket" {
  command = plan
  module {
    source = "../../modules/s3-website"
  }
  variables {
    bucket_name = "lesson12-dev-123456789012"
  }
  assert {
    condition = (
      aws_s3_bucket_public_access_block.website.block_public_acls &&
      aws_s3_bucket_public_access_block.website.block_public_policy &&
      aws_s3_bucket_public_access_block.website.ignore_public_acls &&
      aws_s3_bucket_public_access_block.website.restrict_public_buckets &&
      !aws_s3_bucket.website.force_destroy &&
      aws_s3_bucket_ownership_controls.website.rule[0].object_ownership == "BucketOwnerEnforced" &&
      one(aws_s3_bucket_server_side_encryption_configuration.website.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    )
    error_message = "The bucket must remain private and preserve uploaded files on destroy by default."
  }
}

run "https_spa" {
  command = plan
  module {
    source = "../../modules/cloudfront-spa"
  }

  variables {
    name                        = "lesson12-dev-123456789012"
    bucket_regional_domain_name = "lesson12-dev-123456789012.s3.ap-southeast-1.amazonaws.com"
  }
  assert {
    condition = (
      aws_cloudfront_origin_access_control.website.signing_behavior == "always" &&
      aws_cloudfront_distribution.website.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https" &&
      aws_cloudfront_distribution.website.default_root_object == "index.html" &&
      length(aws_cloudfront_distribution.website.default_cache_behavior[0].function_association) == 0 &&
      aws_cloudfront_cache_policy.website.min_ttl == 0 &&
      aws_cloudfront_cache_policy.website.default_ttl == 0 &&
      aws_cloudfront_cache_policy.website.max_ttl == 31536000 &&
      length(aws_cloudfront_distribution.website.custom_error_response) == 0
    )
    error_message = "CloudFront must sign origin requests, enforce HTTPS, serve index.html without edge functions, and respect no-cache headers."
  }
}

run "bucket_policy" {
  command = apply

  assert {
    condition = (
      local.name == "lesson12-dev-123456789012" &&
      jsondecode(aws_s3_bucket_policy.cloudfront.policy).Statement[0].Principal.Service == "cloudfront.amazonaws.com" &&
      jsondecode(aws_s3_bucket_policy.cloudfront.policy).Statement[0].Action == "s3:GetObject" &&
      jsondecode(aws_s3_bucket_policy.cloudfront.policy).Statement[0].Condition.StringEquals["AWS:SourceArn"] == module.cloudfront.distribution_arn &&
      jsondecode(aws_s3_bucket_policy.cloudfront.policy).Statement[1].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.cloudfront.policy).Statement[1].Condition.Bool["aws:SecureTransport"] == "false"
    )
    error_message = "The dev root must restrict S3 reads to its CloudFront distribution and deny insecure transport."
  }
}
