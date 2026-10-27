# DynamoDB table

Reusable module: an on-demand (`PAY_PER_REQUEST`) DynamoDB table with point-in-time recovery and KMS encryption at rest. It declares only the key attributes, because DynamoDB has no schema for other attributes.

| Input | Default | Purpose |
| --- | --- | --- |
| `name` | Required | Table name, 3–255 characters, unique per account and region |
| `hash_key` | Required | Partition key attribute, e.g. `id` |
| `hash_key_type` | `S` | `S` string, `N` number or `B` binary |
| `range_key` | `null` | Optional sort key; `null` = partition key only |
| `range_key_type` | `S` | Sort key type, used only with `range_key` |
| `point_in_time_recovery` | `true` | Continuous backups; restore to any second in the last 35 days |
| `deletion_protection` | `false` | Blocks `DeleteTable`, including `terraform destroy`. Turn it on for data that matters |
| `kms_key_arn` | `null` | Customer managed key; `null` = AWS managed key `aws/dynamodb` |

Outputs: `table_name`, `table_arn`.

Grant access by passing `table_arn` into a least-privilege IAM policy that lists only the actions the code needs. The [dev root](../../environments/dev/main.tf) gives the function `dynamodb:GetItem` and `dynamodb:Scan` on this one table through the lambda-function module's `inline_policies` input.

> [!NOTE]
> Changing `name`, `hash_key` or `range_key` **replaces** the table, and all its data is lost. Read the plan for `must be replaced` before you apply.
