output "web_acl_arn" {
  description = "Web ACL ARN, for the s3-cloudfront web_acl_arn input."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_name" {
  description = "Web ACL name, the WebACL dimension for CloudWatch widgets and alarms."
  value       = aws_wafv2_web_acl.this.name
}

output "ops_topic_arn" {
  description = "WAF ops SNS topic ARN (in us-east-1, the alarm's region); subscribe more endpoints here."
  value       = aws_sns_topic.ops.arn
}
