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

run "patching_and_snapshot_tags" {
  command = plan
  assert {
    condition     = aws_db_instance.main.auto_minor_version_upgrade && aws_db_instance.main.copy_tags_to_snapshot && !aws_db_instance.main.publicly_accessible && aws_db_instance.main.storage_encrypted
    error_message = "The DB must stay private, encrypted, patched and tag its snapshots."
  }
}

run "reject_bad_inputs" {
  command = plan
  variables {
    name                      = "Bad--Name"
    subnet_ids                = ["subnet-0123456789abcdef0"]
    db_name                   = "1app"
    username                  = "app-user"
    backup_retention_period   = 36
    final_snapshot_identifier = "final-"
    engine_version            = "17.2"
  }
  expect_failures = [var.name, var.subnet_ids, var.db_name, var.username, var.backup_retention_period, var.final_snapshot_identifier, var.engine_version]
}
