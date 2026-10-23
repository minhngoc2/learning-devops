mock_provider "aws" {}

variables {
  name = "lesson10-11-api"
}

run "immutable_scanned_repository" {
  command = plan
  assert {
    condition     = aws_ecr_repository.api.image_tag_mutability == "IMMUTABLE" && aws_ecr_repository.api.image_scanning_configuration[0].scan_on_push && !aws_ecr_repository.api.force_delete
    error_message = "Tags must be immutable, images scanned on push, and destroy must keep images by default."
  }
  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.api.policy).rules[0].selection.countNumber == 10
    error_message = "The lifecycle policy must keep the last 10 images."
  }
}

run "reject_bad_name" {
  command = plan
  variables {
    name = "Lesson10_API-"
  }
  expect_failures = [var.name]
}
