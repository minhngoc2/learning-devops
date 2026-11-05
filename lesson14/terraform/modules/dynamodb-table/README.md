# DynamoDB table

On-demand (`PAY_PER_REQUEST`) DynamoDB table with point-in-time recovery, KMS encryption at rest, and optional TTL. It declares only the key attributes, because DynamoDB has no schema for other attributes. Changing `name`, `hash_key` or `range_key` **replaces** the table and loses its data.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | Table name: 3–255 letters/digits/`_`/`-`/`.`, unique per account and region |
| `hash_key` | Required | Partition key attribute, e.g. `id` |
| `hash_key_type` | `"S"` | `S`, `N` or `B` |
| `range_key` | `null` | Optional sort key; `null` = partition key only |
| `range_key_type` | `"S"` | `S`, `N` or `B`; used only with `range_key` |
| `point_in_time_recovery` | `true` | Restore to any second in the last 35 days |
| `deletion_protection` | `false` | Blocks `DeleteTable`, including `terraform destroy` |
| `kms_key_arn` | `null` | Customer managed key; `null` = AWS managed key `aws/dynamodb` |
| `ttl_attribute` | `null` | Number attribute (epoch seconds) that expires items; `null` = TTL off |

| Output | Use |
| --- | --- |
| `table_name` | Service `TABLE_NAME` environment variable |
| `table_arn` | Least-privilege IAM policy resource |

```hcl
module "cart_table" {
  source        = "../../modules/dynamodb-table"
  name          = "lesson14-dev-cart"
  hash_key      = "customer_sub"
  ttl_attribute = "ttl"
}
```

Tests: [`tests/dynamodb_table.tftest.hcl`](tests/dynamodb_table.tftest.hcl).
