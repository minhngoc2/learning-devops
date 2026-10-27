locals {
  name = "${var.project}-dev"

  # Sample users, keyed by id so adding or removing one never touches the others.
  seed_users = var.seed_users ? { for u in jsondecode(file("${path.module}/seed/users.json")) : u.id => u } : {}
}

module "users_table" {
  source = "../../modules/dynamodb-table"

  name     = "${local.name}-users"
  hash_key = "id"
}

# Lab convenience: Terraform owns these sample rows. Real user data is written by the app, never by Terraform.
resource "aws_dynamodb_table_item" "seed_user" {
  for_each = local.seed_users

  table_name = module.users_table.table_name
  hash_key   = "id"
  item       = jsonencode({ for k, v in each.value : k => { S = tostring(v) } })
}

# Zips only the handler: boto3 ships with the Lambda Python runtime, and the tests stay out of the package.
data "archive_file" "app" {
  type        = "zip"
  source_file = "${path.module}/../../../app/handler.py"
  output_path = "${path.module}/../../../build/function.zip"

  # Fixed mode: keeps the zip hash identical on every machine, whatever its umask.
  output_file_mode = "0644"
}

module "lambda_function" {
  source = "../../modules/lambda-function"

  function_name = local.name
  package_path  = data.archive_file.app.output_path
  runtime       = "python3.13"
  handler       = "handler.lambda_handler" # <file without .py>.<function>
  architectures = ["arm64"]
  memory_size   = var.lambda_memory_size
  timeout       = 10
  log_format    = "JSON"

  environment_variables = {
    TABLE_NAME = module.users_table.table_name
    LOG_LEVEL  = "INFO"
  }

  # Read-only, one table: the function can list and fetch users, not write or delete them.
  inline_policies = {
    users-table-read = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "ReadUsersTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Scan"]
        Resource = module.users_table.table_arn
      }]
    })
  }
}

module "api_gateway" {
  source = "../../modules/api-gateway"

  name                 = local.name
  lambda_function_name = module.lambda_function.function_name
  lambda_invoke_arn    = module.lambda_function.invoke_arn
  routes               = ["GET /health", "GET /users", "GET /users/{id}"]
}
