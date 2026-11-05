# Mocked AWS: no credentials or real resources.
mock_provider "aws" {
  mock_resource "aws_cognito_user_pool" {
    defaults = {
      id       = "ap-southeast-1_example"
      endpoint = "cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_example"
    }
  }
}

variables {
  name = "lesson14-dev"
}

run "email_username_public_client" {
  command = plan

  assert {
    condition = (
      aws_cognito_user_pool.this.username_attributes == toset(["email"]) &&
      aws_cognito_user_pool.this.auto_verified_attributes == toset(["email"]) &&
      aws_cognito_user_pool.this.deletion_protection == "INACTIVE"
    )
    error_message = "Users must sign in with a verified email, and the pool must stay deletable."
  }
  assert {
    condition     = one(aws_cognito_user_pool.this.password_policy).minimum_length == 8
    error_message = "The default minimum password length must be 8."
  }
  assert {
    condition = (
      one([for s in aws_cognito_user_pool.this.schema : s if s.name == "email"]).required &&
      one(one(aws_cognito_user_pool.this.account_recovery_setting).recovery_mechanism).name == "verified_email"
    )
    error_message = "email must be a required attribute and the account recovery channel."
  }
  assert {
    condition = (
      !aws_cognito_user_pool_client.this.generate_secret &&
      aws_cognito_user_pool_client.this.explicit_auth_flows == toset(["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]) &&
      aws_cognito_user_pool_client.this.prevent_user_existence_errors == "ENABLED" &&
      aws_cognito_user_pool_client.this.id_token_validity == 60 &&
      one(aws_cognito_user_pool_client.this.token_validity_units).id_token == "minutes"
    )
    error_message = "The client must be public (no secret), password + refresh flows, hide user existence, 60-minute ID tokens."
  }
}

run "issuer_format" {
  command = apply # the pool ID is only known after (mocked) apply

  assert {
    condition     = strcontains(output.issuer, "cognito-idp.") && output.issuer == "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_example"
    error_message = "issuer must be https://cognito-idp.<region>.amazonaws.com/<pool_id>."
  }
}

run "reject_short_password_policy" {
  command = plan
  variables {
    password_minimum_length = 5
  }
  expect_failures = [var.password_minimum_length]
}
