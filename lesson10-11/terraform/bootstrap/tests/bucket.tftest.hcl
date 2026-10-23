mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

run "protected_state_bucket" {
  command = plan
  assert {
    condition     = aws_s3_bucket.tfstate.bucket == "lesson10-11-tfstate-123456789012-ap-southeast-1"
    error_message = "The bucket name must be <project>-tfstate-<account>-<region>."
  }
  assert {
    condition     = aws_s3_bucket_versioning.tfstate.versioning_configuration[0].status == "Enabled" && aws_s3_bucket_public_access_block.tfstate.restrict_public_buckets
    error_message = "State must be versioned and never public."
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.tfstate.rule).noncurrent_version_expiration[0].noncurrent_days == 90
    error_message = "Old state versions must expire after 90 days."
  }
}

run "reject_bad_project" {
  command = plan
  variables {
    project = "Lesson10_11"
  }
  expect_failures = [var.project]
}
