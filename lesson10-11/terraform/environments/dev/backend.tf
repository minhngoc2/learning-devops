# Partial config: values come from dev.backend.hcl (terraform init -backend-config=dev.backend.hcl).
terraform {
  backend "s3" {}
}
