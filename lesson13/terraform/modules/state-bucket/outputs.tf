output "bucket_name" {
  description = "State bucket name; put it in <env>.backend.hcl."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "State bucket ARN, e.g. for IAM policies that grant state access."
  value       = aws_s3_bucket.this.arn
}
