# CloudFront SPA module

Creates a CloudFront distribution, signed S3 Origin Access Control, and cache policy. Viewers use the default CloudFront certificate and are redirected from HTTP to HTTPS. The origin must be an S3 REST endpoint; S3 website endpoints do not support OAC.

| Input | Required/default | Description |
| --- | --- | --- |
| `name` | Required | Unique name for the distribution's supporting resources |
| `bucket_regional_domain_name` | Required | S3 regional REST hostname |
| `min_ttl` | `0` | Minimum cache lifetime in seconds |
| `default_ttl` | `0` | Cache lifetime in seconds when the origin provides no freshness headers |
| `max_ttl` | `31536000` | Maximum cache lifetime in seconds (one year) |

Outputs: `distribution_id`, `distribution_arn`, `domain_name`.

The caller must grant the CloudFront service principal `s3:GetObject` with `AWS:SourceArn` restricted to `distribution_arn`. The [dev root](../../environments/dev/main.tf) handles this policy.

The default root object is `index.html`. Other requests map directly to S3 objects; no CloudFront Function or route fallback is configured. Add fallback handling if the app later uses browser-history routes. Query strings stay available to the browser but do not affect static origin content or the cache key; cookies are also excluded.

By default, the cache policy respects object Cache-Control with min/default TTL 0 and max TTL one year. Upload metadata controls HTML freshness and immutable hashed asset caching. TTL inputs must be whole seconds with `0 <= min_ttl <= default_ttl <= max_ttl`. Setting `min_ttl` above zero can force caching even when the origin sends `no-cache`, `no-store`, or `private`. There are no blanket 403/404-to-200 responses.

See [quickstart](../../../quickstart.md) for publishing and invalidation.
