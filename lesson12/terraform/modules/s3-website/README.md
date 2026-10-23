# Private S3 storage

Creates the bucket that holds the generated site. It is **private**: no public policy, no ACLs, no S3 static-website hosting. Only CloudFront reads it, through a bucket policy the caller adds (see the [dev root](../../environments/dev/main.tf)).

**Why private?** A public bucket (especially through its HTTP-only website endpoint) bypasses CloudFront's HTTPS and security headers, has no CDN cache, and exposes every object to direct downloads. Keeping it private and fronting it with CloudFront gives HTTPS, edge caching and one controlled entry point.

## Resources

| Resource | Why |
| --- | --- |
| `aws_s3_bucket.website` | The bucket; `force_destroy` decides whether destroy may delete its objects |
| `aws_s3_bucket_public_access_block.website` | All four blocks on, so no policy or ACL can make it public by mistake |
| `aws_s3_bucket_ownership_controls.website` | `BucketOwnerEnforced`: ACLs disabled, the bucket owner owns every object |
| `aws_s3_bucket_server_side_encryption_configuration.website` | Default encryption at rest with SSE-S3 (`AES256`) |
| `aws_s3_bucket_lifecycle_configuration.website` | Deletes parts of uploads that never finished after 7 days, so they stop being billed |

## Inputs

| Input | Default | Rule | Purpose |
| --- | --- | --- | --- |
| `bucket_name` | Required | 3–63 lowercase letters, digits or hyphens; starts and ends with a letter or digit | Globally unique bucket name. Dots are rejected: they break HTTPS certificate matching on S3 endpoints |
| `force_destroy` | `false` | not null | `true` lets `terraform destroy` delete all uploaded objects |

## Outputs

| Output | Used for |
| --- | --- |
| `bucket_name` | `aws s3 cp` destination for `nuxt-app/.output/public/` |
| `bucket_arn` | Resource in the CloudFront read policy |
| `bucket_regional_domain_name` | CloudFront origin (`<bucket>.s3.<region>.amazonaws.com`, the REST endpoint) |

## Usage

```hcl
module "s3_website" {
  source = "../../modules/s3-website"

  bucket_name   = "lesson12-dev-123456789012"
  force_destroy = true # disposable lab only
}
```

The caller must add an `aws_s3_bucket_policy` granting `s3:GetObject` to `cloudfront.amazonaws.com` with an `AWS:SourceArn` condition, as the [dev root](../../environments/dev/main.tf) does. See the [quickstart](../../../quickstart.md) for upload and cleanup.
