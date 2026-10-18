mock_provider "aws" {}

variables {
  name       = "test-staging"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
}

run "protected_defaults" {
  command = plan
  assert {
    condition     = aws_db_instance.main.deletion_protection && !aws_db_instance.main.skip_final_snapshot && aws_db_instance.main.final_snapshot_identifier == "test-staging-final"
    error_message = "Keep the existing protected defaults and default final snapshot name."
  }
}

run "unique_final_snapshot" {
  command = plan
  variables {
    final_snapshot_identifier = "test-staging-final-20261016"
  }
  assert {
    condition     = aws_db_instance.main.final_snapshot_identifier == "test-staging-final-20261016"
    error_message = "An explicit unique final snapshot name must reach RDS."
  }
}

run "dev_skips_final_snapshot" {
  command = plan
  variables {
    skip_final_snapshot = true
  }
  assert {
    condition     = aws_db_instance.main.final_snapshot_identifier == null
    error_message = "Dev must still omit the final snapshot identifier when skipping."
  }
}
