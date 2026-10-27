# Mocked AWS: no credentials or real resources.
mock_provider "aws" {}

variables {
  name     = "lesson12-13-dev-users"
  hash_key = "id"
}

run "on_demand_encrypted_table" {
  command = apply

  assert {
    condition = (
      aws_dynamodb_table.this.name == var.name &&
      output.table_name == var.name &&
      aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST" &&
      aws_dynamodb_table.this.hash_key == "id" &&
      aws_dynamodb_table.this.range_key == null
    )
    error_message = "The table must be on-demand, keyed by hash_key only, and use name as-is."
  }
  assert {
    condition     = [for a in aws_dynamodb_table.this.attribute : "${a.name}:${a.type}"] == ["id:S"]
    error_message = "Only key attributes may be declared."
  }
  assert {
    condition = (
      aws_dynamodb_table.this.point_in_time_recovery[0].enabled &&
      aws_dynamodb_table.this.server_side_encryption[0].enabled &&
      !aws_dynamodb_table.this.deletion_protection_enabled
    )
    error_message = "Defaults: PITR on, KMS encryption on, deletion protection off (lab)."
  }
}

run "composite_key" {
  command = plan
  variables {
    hash_key            = "pk"
    range_key           = "created_at"
    range_key_type      = "N"
    deletion_protection = true
  }
  assert {
    condition = (
      aws_dynamodb_table.this.range_key == "created_at" &&
      toset([for a in aws_dynamodb_table.this.attribute : "${a.name}:${a.type}"]) == toset(["pk:S", "created_at:N"]) &&
      aws_dynamodb_table.this.deletion_protection_enabled
    )
    error_message = "range_key must add a typed sort key attribute; deletion_protection must pass through."
  }
}

run "reject_bad_inputs" {
  command = plan
  variables {
    name           = "x"
    hash_key_type  = "STRING"
    range_key_type = "BOOL"
  }
  expect_failures = [var.name, var.hash_key_type, var.range_key_type]
}
