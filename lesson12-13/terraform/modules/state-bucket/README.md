# State bucket

Reusable module: a private, versioned, encrypted S3 bucket for Terraform remote state with S3-native locking (`use_lockfile`, Terraform 1.10+). Old state versions expire after a rollback window, and plain-HTTP requests are denied.

| Input | Default | Purpose |
| --- | --- | --- |
| `bucket_name` | Required | Globally unique name, 3–63 lowercase characters, e.g. `<project>-tfstate-<account-id>-<region>` |
| `noncurrent_version_expiration_days` | `90` | How long old state versions are kept for rollback |

Outputs: `bucket_name`, `bucket_arn`.

> [!WARNING]
> The bucket has `prevent_destroy = true`, so `terraform destroy` fails on purpose. To remove it, first destroy every stack whose state it holds, then follow the [quickstart's last step](../../../quickstart.md#9-optional-remove-the-state-bucket).

Example use: the [bootstrap root](../../bootstrap/main.tf).
