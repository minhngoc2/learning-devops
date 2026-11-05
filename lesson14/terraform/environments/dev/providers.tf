provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.default_tags
  }
}

# CLOUDFRONT-scope WAF web ACLs and their metrics live in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.default_tags
  }
}
