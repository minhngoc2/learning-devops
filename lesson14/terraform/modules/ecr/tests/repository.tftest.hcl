# Mocked AWS: no credentials or real resources.
mock_provider "aws" {}

variables {
  names = ["lesson14/user", "lesson14/product", "lesson14/cart"]
}

run "one_repository_per_name" {
  command = plan

  assert {
    condition     = length(aws_ecr_repository.this) == 3 && toset(keys(aws_ecr_repository.this)) == var.names
    error_message = "There must be exactly one repository per name."
  }
  assert {
    condition = alltrue([
      for r in aws_ecr_repository.this : r.image_tag_mutability == "IMMUTABLE" && r.image_scanning_configuration[0].scan_on_push && !r.force_delete
    ])
    error_message = "Tags must be immutable, images scanned on push, and destroy must keep images by default."
  }
  assert {
    condition = alltrue([
      for p in aws_ecr_lifecycle_policy.this : jsondecode(p.policy).rules[0].selection.countNumber == 10
    ])
    error_message = "Every lifecycle policy must keep the last 10 images."
  }
}

run "force_delete_passthrough" {
  command = plan
  variables {
    force_delete = true
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.force_delete])
    error_message = "force_delete must reach every repository."
  }
}

run "reject_bad_name" {
  command = plan
  variables {
    names = ["lesson14/user", "Lesson14_API-"]
  }
  expect_failures = [var.names]
}
