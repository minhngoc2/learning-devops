# CloudFront delivery

Creates a distribution, Origin Access Control (OAC), and cache policy. CloudFront redirects HTTP to HTTPS and signs S3 REST-origin requests with SigV4. S3 website endpoints are not supported.

| Input | Default | Purpose |
| --- | --- | --- |
| `name` | Required | Resource name prefix |
| `bucket_regional_domain_name` | Required | S3 REST origin hostname |
| `min_ttl` | `0` | Minimum cache lifetime, seconds |
| `default_ttl` | `0` | Lifetime when freshness headers are absent |
| `max_ttl` | `31536000` | Maximum cache lifetime, seconds |

Outputs: `distribution_id`, `distribution_arn`, `domain_name`.

The [dev root](../../environments/dev/main.tf) grants `cloudfront.amazonaws.com` read access restricted to this distribution's `AWS:SourceArn`.

Only `/` maps to `index.html`; other paths map directly to S3 keys. No URL rewrite or error fallback is configured. Cookies and query strings are excluded from the cache key.

Object `Cache-Control` controls freshness within the TTL limits. TTLs must be whole seconds with `0 <= min_ttl <= default_ttl <= max_ttl`. A positive `min_ttl` can override `no-cache`, `no-store`, and `private`; keep it at zero for this lab.

See the [quickstart](../../../quickstart.md) for upload metadata and invalidation.
