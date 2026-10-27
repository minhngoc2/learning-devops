terraform {
  backend "s3" {} # settings come from dev.backend.hcl: init -backend-config=dev.backend.hcl
}
