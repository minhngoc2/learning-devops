data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

module "s3_website" {
  source = "../../modules/s3-website"

  bucket_name   = local.name
  force_destroy = var.force_destroy
}

module "cloudfront" {
  source = "../../modules/cloudfront-spa"

  name                        = local.name
  bucket_regional_domain_name = module.s3_website.bucket_regional_domain_name
}

resource "aws_s3_bucket_policy" "cloudfront" {
  bucket = module.s3_website.bucket_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontReadOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${module.s3_website.bucket_arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = module.cloudfront.distribution_arn
        }
      }
      }, {
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        module.s3_website.bucket_arn,
        "${module.s3_website.bucket_arn}/*"
      ]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
