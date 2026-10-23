# Lint config for lesson 12. Run from lesson12/:
#   tflint --chdir=terraform --init                                                # once: downloads the AWS plugin
#   tflint --chdir=terraform --recursive --config="$PWD/terraform/.tflint.hcl"
# --config must be absolute: with --recursive, tflint otherwise looks for a config in each
# subfolder and silently falls back to default rules (no AWS checks) where none exists.
config {
  call_module_type = "local" # also lint the modules as called by the dev root
}

plugin "terraform" {
  enabled = true
  preset  = "all"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
