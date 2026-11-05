# Mocked AWS: no credentials or real resources.
mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:111111111111:lesson14-dev-waf-ops"
    }
  }
}

variables {
  name = "lesson14-dev"
}

run "cloudfront_scope_three_rules" {
  command = plan

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "CLOUDFRONT" && length(one(aws_wafv2_web_acl.this.default_action).allow) == 1
    error_message = "The web ACL must be CLOUDFRONT scope and allow by default."
  }
  assert {
    condition = (
      length(aws_wafv2_web_acl.this.rule) == 3 &&
      toset([for r in aws_wafv2_web_acl.this.rule : r.name]) == toset(["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet", "rate-limit"]) &&
      toset([for r in aws_wafv2_web_acl.this.rule : r.priority]) == toset([1, 2, 3])
    )
    error_message = "The web ACL must have the two managed rule groups and the rate-limit rule at priorities 1–3."
  }
  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule :
      one(one(r.statement).rate_based_statement).limit == 2000 &&
      one(one(r.statement).rate_based_statement).aggregate_key_type == "IP" &&
      length(one(r.action).block) == 1
      if r.name == "rate-limit"
    ])
    error_message = "The rate-limit rule must block above 2000 requests per IP (default rate_limit)."
  }
  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule :
      one(r.visibility_config).sampled_requests_enabled && one(r.visibility_config).metric_name == "lesson14-dev-${r.name}"
    ])
    error_message = "Every rule must sample requests and use the metric name <name>-<rule>."
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.blocked) == 0 && length(aws_sns_topic_subscription.email) == 0 && aws_sns_topic.ops.name == "lesson14-dev-waf-ops"
    error_message = "Without alarm_email (the default null): no alarm, no subscription, but the topic still exists."
  }
}

run "alarm_only_with_email" {
  command = apply # the topic ARN is only known after (mocked) apply
  variables {
    alarm_email = "ops@example.com"
  }

  assert {
    condition = (
      length(aws_cloudwatch_metric_alarm.blocked) == 1 &&
      contains(aws_cloudwatch_metric_alarm.blocked[0].alarm_actions, aws_sns_topic.ops.arn) &&
      contains(aws_cloudwatch_metric_alarm.blocked[0].ok_actions, aws_sns_topic.ops.arn) &&
      aws_cloudwatch_metric_alarm.blocked[0].namespace == "AWS/WAFV2" &&
      aws_cloudwatch_metric_alarm.blocked[0].metric_name == "BlockedRequests" &&
      aws_cloudwatch_metric_alarm.blocked[0].dimensions == tomap({ WebACL = "lesson14-dev", Region = "Global", Rule = "ALL" }) &&
      aws_cloudwatch_metric_alarm.blocked[0].threshold == 100
    )
    error_message = "With alarm_email, one BlockedRequests alarm (Region=Global) must notify the module's topic."
  }
  assert {
    condition = (
      length(aws_sns_topic_subscription.email) == 1 &&
      aws_sns_topic_subscription.email[0].protocol == "email" &&
      aws_sns_topic_subscription.email[0].endpoint == "ops@example.com" &&
      aws_sns_topic_subscription.email[0].topic_arn == aws_sns_topic.ops.arn &&
      output.ops_topic_arn == aws_sns_topic.ops.arn
    )
    error_message = "alarm_email must add one email subscription to the module's topic."
  }
}

run "reject_bad_rate_limit" {
  command = plan
  variables {
    rate_limit = 50
  }
  expect_failures = [var.rate_limit]
}
