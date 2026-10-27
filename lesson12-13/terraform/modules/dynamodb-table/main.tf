locals {
  # A key attribute is declared once even if hash and range key share a type; only key attributes may be listed.
  key_attributes = merge(
    { (var.hash_key) = var.hash_key_type },
    var.range_key == null ? {} : { (var.range_key) = var.range_key_type },
  )
}

# On-demand table: no capacity to size, pay per request, scales to zero cost when idle (storage aside).
resource "aws_dynamodb_table" "this" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = var.hash_key
  range_key    = var.range_key

  dynamic "attribute" {
    for_each = local.key_attributes
    content {
      name = attribute.key
      type = attribute.value
    }
  }

  # Continuous backups: restore to any second in the last 35 days.
  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  # Encryption at rest is always on. enabled = true uses KMS: the AWS managed key (aws/dynamodb), or kms_key_arn if set.
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  deletion_protection_enabled = var.deletion_protection
}
