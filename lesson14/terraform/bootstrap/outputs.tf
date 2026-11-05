output "state_bucket" {
  description = "Put this in environments/dev/dev.backend.hcl as bucket."
  value       = module.state_bucket.bucket_name
}
