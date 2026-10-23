locals {
  name = "${var.project}-dev"
}

# Zips the Linux/arm64 binary built by the quickstart (lesson13/build/bootstrap).
data "archive_file" "app" {
  type        = "zip"
  source_file = "${path.module}/../../../build/bootstrap"
  output_path = "${path.module}/../../../build/function.zip"

  # Fixed mode: keeps bootstrap executable and the zip hash identical on every machine, whatever its umask.
  output_file_mode = "0755"
}

module "lambda_function" {
  source = "../../modules/lambda-function"

  function_name = local.name
  package_path  = data.archive_file.app.output_path
  runtime       = "provided.al2023" # Go has no managed runtime; the zip ships its own bootstrap executable.
  handler       = "bootstrap"
  architectures = ["arm64"]

  environment_variables = {
    GREETING = var.greeting
  }
}

module "api_gateway" {
  source = "../../modules/api-gateway"

  name                 = local.name
  lambda_function_name = module.lambda_function.function_name
  lambda_invoke_arn    = module.lambda_function.invoke_arn
  routes               = ["GET /health", "GET /hello", "POST /echo"]
}
