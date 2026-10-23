mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  # Realistic value so the cloudfront-spa origin validation sees a REST endpoint, not random mock text.
  mock_resource "aws_s3_bucket" {
    defaults = {
      bucket_regional_domain_name = "lesson12-dev-123456789012.s3.ap-southeast-1.amazonaws.com"
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
      one(aws_s3_bucket_server_side_encryption_configuration.website.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" &&
      one(aws_s3_bucket_lifecycle_configuration.website.rule).abort_incomplete_multipart_upload[0].days_after_initiation == 7
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
      length(aws_cloudfront_distribution.website.custom_error_response) == 0 &&
      aws_cloudfront_distribution.website.default_cache_behavior[0].response_headers_policy_id == data.aws_cloudfront_response_headers_policy.security.id &&
      data.aws_cloudfront_response_headers_policy.security.name == "Managed-SecurityHeadersPolicy"
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

# Every validation rule must reject bad input; expect_failures fails the run if a rule does not trigger.
run "reject_bad_root_inputs" {
  command = plan
  variables {
    aws_region = "Singapore"
    project    = "Lesson_12"
  }
  expect_failures = [var.aws_region, var.project]
}

run "reject_bad_bucket_name" {
  command = plan
  module {
    source = "../../modules/s3-website"
  }
  variables {
    bucket_name = "My.Bucket"
  }
  expect_failures = [var.bucket_name]
}

run "reject_bad_cloudfront_inputs" {
  command = plan
  module {
    source = "../../modules/cloudfront-spa"
  }
  variables {
    name                        = "has spaces"
    bucket_regional_domain_name = "lesson12-dev-123456789012.s3-website-ap-southeast-1.amazonaws.com"
    min_ttl                     = -1
  }
  expect_failures = [var.name, var.bucket_regional_domain_name, var.min_ttl]
}

# One ordering rule per run: a variable that fails its own rule cannot be used to check the next one.
run "reject_default_ttl_below_min" {
  command = plan
  module {
    source = "../../modules/cloudfront-spa"
  }
  variables {
    name                        = "lesson12-dev-123456789012"
    bucket_regional_domain_name = "lesson12-dev-123456789012.s3.ap-southeast-1.amazonaws.com"
    min_ttl                     = 10
    default_ttl                 = 5
  }
  expect_failures = [var.default_ttl]
}

run "reject_max_ttl_below_default" {
  command = plan
  module {
    source = "../../modules/cloudfront-spa"
  }
  variables {
    name                        = "lesson12-dev-123456789012"
    bucket_regional_domain_name = "lesson12-dev-123456789012.s3.ap-southeast-1.amazonaws.com"
    default_ttl                 = 10
    max_ttl                     = 5
  }
  expect_failures = [var.max_ttl]
}
