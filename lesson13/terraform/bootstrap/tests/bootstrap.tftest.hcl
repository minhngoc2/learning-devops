# Mocked AWS: no credentials or real resources.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

run "bucket_name_format" {
  command = apply

  assert {
    condition     = output.state_bucket == "lesson13-tfstate-123456789012-ap-southeast-1"
    error_message = "The bucket name must be <project>-tfstate-<account-id>-<region>."
  }
}

run "reject_bad_project" {
  command = plan
  variables {
    project = "Lesson_13"
  }
  expect_failures = [var.project]
}
