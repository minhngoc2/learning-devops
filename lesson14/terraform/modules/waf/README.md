# WAF web ACL

CLOUDFRONT-scope WAFv2 web ACL for the distribution: default allow, then AWS managed `AWSManagedRulesCommonRuleSet` (priority 1) and `AWSManagedRulesKnownBadInputsRuleSet` (2), then a rate-based rule (3) that blocks any IP above `rate_limit` requests per 5 minutes. Every rule samples requests and publishes CloudWatch metrics as `<name>-<rule>`. The module owns an ops SNS topic (`<name>-waf-ops`) in us-east-1, because a CloudWatch alarm can only notify a topic in its own region. With `alarm_email` set, it subscribes that address and adds a `BlockedRequests` alarm (sum over 5 minutes, all rules, dimension `Region = Global` as WAF publishes CLOUDFRONT-scope metrics) that notifies the topic on ALARM and OK. CLOUDFRONT scope only exists in us-east-1, so the caller passes a us-east-1 provider; the module itself declares no alias.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | Web ACL name and metric prefix; 1–100 letters/digits/`-`/`_` |
| `rate_limit` | `2000` | Requests per IP per 5 minutes before blocking; ≥ 100 (WAF minimum) |
| `blocked_requests_threshold` | `100` | Blocked requests per 5 minutes that trigger the alarm |
| `alarm_email` | `null` | Email subscribed to the us-east-1 ops topic (confirm it); `null` = no subscription and no alarm |

| Output | Use |
| --- | --- |
| `web_acl_arn` | s3-cloudfront `web_acl_arn` |
| `web_acl_name` | CloudWatch `WebACL` dimension (observability dashboard) |
| `ops_topic_arn` | The us-east-1 ops topic, for extra subscriptions |

```hcl
module "waf" {
  source      = "../../modules/waf"
  providers   = { aws = aws.us_east_1 }
  name        = "lesson14-dev"
  alarm_email = var.alarm_email
}
```

Tests: [`tests/waf.tftest.hcl`](tests/waf.tftest.hcl).
