# CLOUDFRONT-scope ACLs live in us-east-1: the caller passes an aws provider configured for that region.
resource "aws_wafv2_web_acl" "this" {
  name        = var.name
  description = "Edge protection for the ${var.name} CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-limit"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }
}

# CloudWatch alarms can only notify SNS topics in their own region, so the us-east-1 alarm gets its own topic.
resource "aws_sns_topic" "ops" {
  name = "${var.name}-waf-ops"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.ops.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "blocked" {
  count = var.alarm_email == null ? 0 : 1

  alarm_name          = "${var.name}-waf-blocked-requests"
  alarm_description   = "WAF blocked more than ${var.blocked_requests_threshold} requests in 5 minutes"
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  dimensions          = { WebACL = var.name, Region = "Global", Rule = "ALL" } # CLOUDFRONT-scope metrics use Region=Global
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.blocked_requests_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]
}
