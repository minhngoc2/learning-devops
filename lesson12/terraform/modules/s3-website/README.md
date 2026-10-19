# S3 website files module

Creates a private S3 bucket for static SPA files, AES256 encryption, enforced bucket ownership, and all four public-access blocks. It does not enable S3 website hosting or manage uploaded objects.

| Input | Required/default | Description |
| --- | --- | --- |
| `bucket_name` | Required | Globally unique bucket name |
| `force_destroy` | `false` | Permit deletion of all contents during destroy |

Outputs: `bucket_name`, `bucket_arn`, `bucket_regional_domain_name`.

The environment root attaches the bucket policy after composing this module with CloudFront. Only that distribution gets `s3:GetObject`; the root also denies non-HTTPS access. See [dev/main.tf](../../environments/dev/main.tf) and [quickstart](../../../quickstart.md).
