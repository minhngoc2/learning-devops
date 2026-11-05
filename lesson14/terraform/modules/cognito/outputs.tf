output "user_pool_id" {
  description = "User pool ID, e.g. for aws cognito-idp admin-* commands."
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "User pool ARN, for IAM policies."
  value       = aws_cognito_user_pool.this.arn
}

output "issuer" {
  description = "JWT issuer, https://cognito-idp.<region>.amazonaws.com/<pool_id>, for the API Gateway JWT authorizer."
  value       = "https://${aws_cognito_user_pool.this.endpoint}"
}

output "client_id" {
  description = "Public app client ID: the JWT audience and the storefront's sign-in client."
  value       = aws_cognito_user_pool_client.this.id
}
