# Private S3 storage

Creates a bucket with AES256 encryption, `BucketOwnerEnforced` ownership, and all four public-access blocks. S3 website hosting stays disabled; uploads are managed separately.

| Input | Default | Purpose |
| --- | --- | --- |
| `bucket_name` | Required | Globally unique bucket name |
| `force_destroy` | `false` | Allow destroy to delete all objects |

Outputs: `bucket_name`, `bucket_arn`, `bucket_regional_domain_name`.

The [dev root](../../environments/dev/main.tf) grants CloudFront read access scoped to its distribution and denies non-TLS requests. See the [quickstart](../../../quickstart.md) for deployment and cleanup.
