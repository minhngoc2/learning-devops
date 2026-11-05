output "web_acl_arn" {
  description = "Web ACL ARN, for the s3-cloudfront web_acl_arn input."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_name" {
  description = "Web ACL name, the WebACL dimension for CloudWatch widgets and alarms."
  value       = aws_wafv2_web_acl.this.name
}
