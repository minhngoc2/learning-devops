# Run once with local state: creates the S3 bucket that environments/dev uses as its backend.
data "aws_caller_identity" "current" {}

module "state_bucket" {
  source = "../modules/state-bucket"

  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}
