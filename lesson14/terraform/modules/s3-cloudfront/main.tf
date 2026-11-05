data "aws_caller_identity" "current" {}

locals {
  # The account ID keeps the globally unique bucket names stable and collision-free.
  buckets = {
    storefront = "${var.name}-storefront-${data.aws_caller_identity.current.account_id}"
    images     = "${var.name}-images-${data.aws_caller_identity.current.account_id}"
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket        = each.value
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Only this distribution, signing through OAC, may read objects; the buckets stay private.
resource "aws_s3_bucket_policy" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${each.value.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.this.arn } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = var.name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "spa" {
  name    = "${var.name}-spa-fallback"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite extension-less paths to /index.html"
  publish = true
  code    = file("${path.module}/function.js")
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Forwards every viewer header, cookie and query string except Host, which must be the API Gateway hostname.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.name
  default_root_object = "index.html"
  price_class         = var.price_class
  web_acl_id          = var.web_acl_arn

  origin {
    origin_id                = "storefront"
    domain_name              = aws_s3_bucket.this["storefront"].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  origin {
    origin_id                = "images"
    domain_name              = aws_s3_bucket.this["images"].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  origin {
    origin_id   = "api"
    domain_name = var.api_host

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Proves the request came through CloudFront (and its WAF); requests to execute-api directly lack it.
    custom_header {
      name  = "X-Origin-Verify"
      value = var.origin_verify_secret
    }
  }

  default_cache_behavior {
    target_origin_id       = "storefront"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa.arn
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/images/*"
    target_origin_id       = "images"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
  }

  # No custom_error_response: it would rewrite API 403/404 responses into the SPA shell. The function handles SPA routes.

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
