# CloudFront delivery

Creates the CloudFront distribution that serves the private S3 bucket over HTTPS, its Origin Access Control (OAC), and a cache policy. CloudFront redirects HTTP to HTTPS, signs every origin request with SigV4 through OAC, and adds AWS's managed security headers to every response.

**Why CloudFront in front of S3?** HTTPS on a `*.cloudfront.net` hostname, caching at edge locations close to users, and an S3 bucket that never has to be public.

> **Name note:** despite the `-spa` suffix, this module has **no single-page-app fallback**. Only `/` maps to `index.html`; every other path maps directly to an S3 key, and missing keys return `403` from S3. Nested routes need a CloudFront Function rewrite or a custom error response, which this lab does not add.

## Resources

| Resource | Why |
| --- | --- |
| `aws_cloudfront_origin_access_control.website` | Signs origin requests (`sigv4`, `always`) so the bucket policy can trust CloudFront |
| `aws_cloudfront_cache_policy.website` | TTL limits; cache key ignores cookies, headers and query strings; gzip/brotli variants |
| `data.aws_cloudfront_response_headers_policy.security` | Looks up AWS's `Managed-SecurityHeadersPolicy` (HSTS, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `X-XSS-Protection`) |
| `aws_cloudfront_distribution.website` | One S3 origin, GET/HEAD only, `redirect-to-https`, compression, default certificate |

## Inputs

| Input | Default | Rule | Purpose |
| --- | --- | --- | --- |
| `name` | Required | 1–64 letters, digits, hyphens or underscores | OAC and cache policy name, distribution comment |
| `bucket_regional_domain_name` | Required | Must match `<bucket>.s3[.<region>].amazonaws.com` (or `.amazonaws.com.cn` in China regions) | S3 **REST** endpoint. Website endpoints (`s3-website-…`) are rejected: OAC cannot sign requests to them |
| `min_ttl` | `0` | whole seconds, `>= 0` | Minimum cache lifetime. Above zero it can override `no-cache`, `no-store` and `private` |
| `default_ttl` | `0` | whole seconds, `>= min_ttl` | Lifetime when the object has no `Cache-Control`/`Expires` |
| `max_ttl` | `31536000` | whole seconds, `>= default_ttl` | Upper bound, including objects with freshness headers |

Object `Cache-Control` decides freshness within these limits: the quickstart uploads HTML with `no-cache` and fingerprinted `_nuxt/` assets with `public,max-age=31536000,immutable`.

## Outputs

| Output | Used for |
| --- | --- |
| `distribution_id` | `aws cloudfront create-invalidation` |
| `distribution_arn` | `AWS:SourceArn` condition in the S3 bucket policy |
| `domain_name` | The site's `https://<id>.cloudfront.net` hostname |

## Usage

```hcl
module "cloudfront" {
  source = "../../modules/cloudfront-spa"

  name                        = "lesson12-dev-123456789012"
  bucket_regional_domain_name = module.s3_website.bucket_regional_domain_name
}
```

The [dev root](../../environments/dev/main.tf) wires this to the bucket and adds the bucket policy restricted to this distribution's ARN. See the [quickstart](../../../quickstart.md) for upload metadata and invalidation.
