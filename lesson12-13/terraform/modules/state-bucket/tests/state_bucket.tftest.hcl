# Mocked AWS: no credentials or real resources.
mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::lesson12-13-tfstate-123456789012-ap-southeast-1"
    }
  }
}

variables {
  bucket_name = "lesson12-13-tfstate-123456789012-ap-southeast-1"
}

run "hardened_bucket" {
  command = apply

  assert {
    condition     = aws_s3_bucket.this.bucket == var.bucket_name && output.bucket_name == var.bucket_name
    error_message = "The bucket must use bucket_name as-is."
  }
  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "State must be versioned so a bad apply can be rolled back."
  }
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "State must never be public."
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).noncurrent_version_expiration[0].noncurrent_days == 90
    error_message = "Old state versions must expire after 90 days by default."
  }
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "State must be encrypted at rest."
  }
  assert {
    condition     = strcontains(aws_s3_bucket_policy.tls_only.policy, "aws:SecureTransport")
    error_message = "The bucket policy must deny plain HTTP."
  }
}

run "reject_bad_bucket_name" {
  command = plan
  variables {
    bucket_name = "Bad_Name"
  }
  expect_failures = [var.bucket_name]
}

run "reject_bad_expiry" {
  command = plan
  variables {
    noncurrent_version_expiration_days = 0
  }
  expect_failures = [var.noncurrent_version_expiration_days]
}
