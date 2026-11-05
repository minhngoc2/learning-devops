# S3 + CloudFront entry point

One CloudFront distribution in front of everything: the Nuxt storefront from a private S3 bucket (default behaviour), product images from a second private bucket (`/images/*`), and the API Gateway HTTP API (`/api/*`, uncached, all viewer headers except `Host`, all methods). Both buckets are SSE-encrypted, block all public access, and allow `s3:GetObject` only to this distribution through OAC. The API origin gets a secret `X-Origin-Verify` header, so direct `execute-api` calls can be refused. A CloudFront Function ([`function.js`](function.js), viewer-request) rewrites extension-less paths to `/index.html` for SPA routes. There is deliberately **no** `custom_error_response`, which would turn API 403/404 responses into the HTML shell.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | Prefix: 3–32 lowercase letters/digits/hyphens; buckets `<name>-storefront-<account>` and `<name>-images-<account>` |
| `api_host` | Required | Bare API Gateway hostname (api-gateway `api_host` output) |
| `origin_verify_secret` | Required | Sensitive; ≥ 16 characters; sent as `X-Origin-Verify` |
| `web_acl_arn` | `null` | CLOUDFRONT-scope WAFv2 ACL ARN (us-east-1); `null` = no WAF |
| `force_destroy` | `false` | Let destroy empty the buckets (dev sets `true`) |
| `price_class` | `"PriceClass_200"` | `PriceClass_100`, `PriceClass_200` or `PriceClass_All` |

| Output | Use |
| --- | --- |
| `distribution_id` | `aws cloudfront create-invalidation` |
| `distribution_arn` | Reference the distribution |
| `domain_name` | Public URL host, Product Service `PUBLIC_BASE_URL` |
| `storefront_bucket_name` | `aws s3 sync .output/public/` target |
| `images_bucket_name`, `images_bucket_arn` | Image uploads, Product Service `IMAGES_BUCKET` and task policy |

```hcl
module "edge" {
  source               = "../../modules/s3-cloudfront"
  name                 = "lesson14-dev"
  api_host             = module.api.api_host
  origin_verify_secret = random_password.origin_verify.result
  web_acl_arn          = module.waf.web_acl_arn
  force_destroy        = true # dev only
}
```

Tests: [`tests/distribution.tftest.hcl`](tests/distribution.tftest.hcl).
