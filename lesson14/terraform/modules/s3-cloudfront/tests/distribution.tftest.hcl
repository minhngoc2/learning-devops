# Mocked AWS: no credentials or real resources.
# The managed-policy data sources' `id` is optional (not computed) in the provider schema, so mocks leave it null;
# behaviours are therefore checked against the data-source references plus each data source's `name`.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn         = "arn:aws:cloudfront::111111111111:distribution/E2EXAMPLE"
      domain_name = "d111111abcdef8.cloudfront.net"
    }
  }
}

# Distinct function ARNs, so the behaviour assertions can tell the two functions apart.
override_resource {
  target = aws_cloudfront_function.spa
  values = {
    arn = "arn:aws:cloudfront::111111111111:function/lesson14-dev-spa-fallback"
  }
}

override_resource {
  target = aws_cloudfront_function.images_prefix
  values = {
    arn = "arn:aws:cloudfront::111111111111:function/lesson14-dev-images-prefix"
  }
}

variables {
  name                 = "lesson14-dev"
  api_host             = "abc123.execute-api.ap-southeast-1.amazonaws.com"
  origin_verify_secret = "test-origin-verify-secret"
}

run "three_origins_three_behaviours" {
  command = plan

  assert {
    condition     = toset([for o in aws_cloudfront_distribution.this.origin : o.origin_id]) == toset(["storefront", "images", "api"])
    error_message = "The distribution must have exactly the storefront, images and api origins."
  }
  assert {
    condition = (
      one(aws_cloudfront_distribution.this.default_cache_behavior).target_origin_id == "storefront" &&
      one(aws_cloudfront_distribution.this.default_cache_behavior).cache_policy_id == data.aws_cloudfront_cache_policy.caching_optimized.id &&
      data.aws_cloudfront_cache_policy.caching_optimized.name == "Managed-CachingOptimized" &&
      one(aws_cloudfront_distribution.this.default_cache_behavior).viewer_protocol_policy == "redirect-to-https" &&
      length(aws_cloudfront_distribution.this.ordered_cache_behavior) == 2
    )
    error_message = "Default behaviour serves the cached storefront over HTTPS; two ordered behaviours follow."
  }
  assert {
    condition = alltrue([
      for b in aws_cloudfront_distribution.this.ordered_cache_behavior :
      b.target_origin_id == "images" && b.cache_policy_id == data.aws_cloudfront_cache_policy.caching_optimized.id
      if b.path_pattern == "/images/*"
    ])
    error_message = "/images/* must go to the images origin with CachingOptimized."
  }
  assert {
    condition = (
      alltrue([
        for b in aws_cloudfront_distribution.this.ordered_cache_behavior :
        b.target_origin_id == "api" &&
        b.cache_policy_id == data.aws_cloudfront_cache_policy.caching_disabled.id &&
        b.origin_request_policy_id == data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id &&
        contains(b.allowed_methods, "POST")
        if b.path_pattern == "/api/*"
      ]) &&
      length([for b in aws_cloudfront_distribution.this.ordered_cache_behavior : b if b.path_pattern == "/api/*"]) == 1 &&
      data.aws_cloudfront_cache_policy.caching_disabled.name == "Managed-CachingDisabled" &&
      data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.name == "Managed-AllViewerExceptHostHeader"
    )
    error_message = "/api/* must go to the api origin uncached, forward viewer headers except Host, and allow POST."
  }
  assert {
    condition = (
      aws_cloudfront_distribution.this.is_ipv6_enabled &&
      aws_cloudfront_distribution.this.price_class == "PriceClass_200" &&
      aws_cloudfront_distribution.this.web_acl_id == null
    )
    error_message = "Defaults: IPv6 on, PriceClass_200, no WAF when web_acl_arn is null."
  }
}

run "api_origin_sends_verify_header" {
  command = apply # the OAC ID is only known after (mocked) apply

  assert {
    condition = alltrue([
      for o in aws_cloudfront_distribution.this.origin :
      o.domain_name == var.api_host &&
      one(o.custom_origin_config).origin_protocol_policy == "https-only" &&
      one(o.custom_origin_config).origin_ssl_protocols == toset(["TLSv1.2"]) &&
      [for h in o.custom_header : h.value if h.name == "X-Origin-Verify"] == [var.origin_verify_secret]
      if o.origin_id == "api"
    ])
    error_message = "The api origin must be HTTPS-only (TLSv1.2) and send X-Origin-Verify with the secret."
  }
  assert {
    condition = alltrue([
      for o in aws_cloudfront_distribution.this.origin :
      length(o.custom_header) == 0 && o.origin_access_control_id == aws_cloudfront_origin_access_control.this.id
      if o.origin_id != "api"
    ])
    error_message = "S3 origins must use OAC and must not receive the secret header."
  }
}

run "no_custom_error_responses_and_spa_function" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.this.custom_error_response) == 0
    error_message = "No custom_error_response: API 4xx/5xx must reach the client unchanged."
  }
  assert {
    condition = (
      length(one(aws_cloudfront_distribution.this.default_cache_behavior).function_association) == 1 &&
      one(one(aws_cloudfront_distribution.this.default_cache_behavior).function_association).event_type == "viewer-request" &&
      aws_cloudfront_function.spa.runtime == "cloudfront-js-2.0" &&
      strcontains(aws_cloudfront_function.spa.code, "/index.html")
    )
    error_message = "The default behaviour must run the SPA rewrite function on viewer-request."
  }
}

run "buckets_private" {
  command = apply # the distribution ARN is only known after (mocked) apply

  assert {
    condition = alltrue([
      for b in values(aws_s3_bucket_public_access_block.this) :
      b.block_public_acls && b.block_public_policy && b.ignore_public_acls && b.restrict_public_buckets
    ]) && length(aws_s3_bucket_public_access_block.this) == 2
    error_message = "Both buckets must block all public access."
  }
  assert {
    condition = alltrue([
      for k, p in aws_s3_bucket_policy.this :
      jsondecode(p.policy).Statement[0].Principal.Service == "cloudfront.amazonaws.com" &&
      jsondecode(p.policy).Statement[0].Resource == "${aws_s3_bucket.this[k].arn}/*" &&
      jsondecode(p.policy).Statement[0].Condition.StringEquals["AWS:SourceArn"] == aws_cloudfront_distribution.this.arn
    ]) && length(aws_s3_bucket_policy.this) == 2
    error_message = "Both bucket policies must allow only this distribution (OAC) to read objects."
  }
  assert {
    condition = (
      output.storefront_bucket_name == "lesson14-dev-storefront-111111111111" &&
      output.images_bucket_name == "lesson14-dev-images-111111111111" &&
      output.domain_name == "d111111abcdef8.cloudfront.net"
    )
    error_message = "Bucket names are <name>-<role>-<account id>; domain_name is the distribution's."
  }
}

run "images_behaviour_strips_prefix" {
  command = apply # function ARNs are only known after (mocked) apply

  assert {
    condition = alltrue([
      for b in aws_cloudfront_distribution.this.ordered_cache_behavior :
      length(b.function_association) == 1 &&
      one(b.function_association).event_type == "viewer-request" &&
      one(b.function_association).function_arn == aws_cloudfront_function.images_prefix.arn
      if b.path_pattern == "/images/*"
    ])
    error_message = "/images/* must run exactly one viewer-request function: the images prefix function."
  }
  assert {
    condition = (
      one(one(aws_cloudfront_distribution.this.default_cache_behavior).function_association).function_arn == aws_cloudfront_function.spa.arn &&
      aws_cloudfront_function.spa.arn != aws_cloudfront_function.images_prefix.arn
    )
    error_message = "The default behaviour must still run the SPA function."
  }
  assert {
    condition = (
      aws_cloudfront_function.images_prefix.runtime == "cloudfront-js-2.0" &&
      aws_cloudfront_function.images_prefix.name == "lesson14-dev-images-prefix" &&
      strcontains(aws_cloudfront_function.images_prefix.code, "/images")
    )
    error_message = "The images function must be a cloudfront-js-2.0 function named <name>-images-prefix that handles /images."
  }
}
