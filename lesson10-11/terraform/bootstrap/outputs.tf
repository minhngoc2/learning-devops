output "state_bucket" {
  description = "Put this in environments/<env>/<env>.backend.hcl."
  value       = aws_s3_bucket.tfstate.id
}
