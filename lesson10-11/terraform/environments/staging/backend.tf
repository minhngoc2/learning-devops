# Use staging.backend.hcl with a staging-only key. Never copy dev's initialized .terraform directory.
terraform {
  backend "s3" {}
}
