# Cognito user pool

Cognito user pool where customers sign in with a verified email, plus one public app client (no secret) for the storefront using username/password and refresh-token flows. ID tokens last 60 minutes, and failed sign-ins never reveal whether an account exists. Deletion protection is off so the lab can be destroyed.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | Pool name; the client is `<name>-web` |
| `password_minimum_length` | `8` | 8–99; passwords also need upper, lower, number, symbol |

| Output | Use |
| --- | --- |
| `user_pool_id` | `aws cognito-idp admin-*` commands |
| `user_pool_arn` | IAM policies |
| `issuer` | API Gateway JWT authorizer `jwt_issuer` |
| `client_id` | JWT audience and storefront sign-in client |

```hcl
module "cognito" {
  source = "../../modules/cognito"
  name   = "lesson14-dev"
}
```

Tests: [`tests/user_pool.tftest.hcl`](tests/user_pool.tftest.hcl).
