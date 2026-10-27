# Mocked AWS: no credentials or real resources. The archive provider is real and zips app/handler.py.
mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/lesson12-13-dev-lambda"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:ap-southeast-1:123456789012:log-group:/aws/apigateway/lesson12-13-dev"
    }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:ap-southeast-1:123456789012:table/lesson12-13-dev-users"
    }
  }
  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      execution_arn = "arn:aws:execute-api:ap-southeast-1:123456789012:abc123"
      api_endpoint  = "https://abc123.execute-api.ap-southeast-1.amazonaws.com"
    }
  }
  mock_resource "aws_lambda_function" {
    defaults = {
      invoke_arn = "arn:aws:apigateway:ap-southeast-1:lambda:path/2015-03-31/functions/arn:aws:lambda:ap-southeast-1:123456789012:function:lesson12-13-dev/invocations"
    }
  }
}

run "users_api" {
  command = apply

  assert {
    condition = (
      output.function_name == "lesson12-13-dev" &&
      output.table_name == "lesson12-13-dev-users" &&
      output.api_url == "https://abc123.execute-api.ap-southeast-1.amazonaws.com"
    )
    error_message = "The dev root must name resources lesson12-13-dev(-users) and expose the API endpoint."
  }
  assert {
    condition = (
      module.lambda_function.function_name == "lesson12-13-dev" &&
      length(aws_dynamodb_table_item.seed_user) == 5 &&
      jsondecode(aws_dynamodb_table_item.seed_user["u001"].item).name.S == "An Nguyen"
    )
    error_message = "seed/users.json must load 5 users keyed by id, as DynamoDB string attributes."
  }
}

run "lambda_settings" {
  command = plan

  assert {
    condition = (
      module.lambda_function.memory_size == 1024 &&
      output.table_name == "lesson12-13-dev-users"
    )
    error_message = "The function must get 1 GB (1024 MB) of memory by default."
  }
}

run "no_seed" {
  command = plan
  variables {
    seed_users = false
  }
  assert {
    condition     = length(aws_dynamodb_table_item.seed_user) == 0
    error_message = "seed_users = false must create no sample items."
  }
}

run "lambda_function_module" {
  command = plan
  module {
    source = "../../modules/lambda-function"
  }
  variables {
    function_name = "lesson12-13-dev"
    package_path  = "../../../build/function.zip"
    runtime       = "python3.13"
    handler       = "handler.lambda_handler"
    memory_size   = 1024
    log_format    = "JSON"
    environment_variables = {
      TABLE_NAME = "lesson12-13-dev-users"
    }
    inline_policies = {
      users-table-read = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"dynamodb:GetItem\",\"dynamodb:Scan\"],\"Resource\":\"arn:aws:dynamodb:ap-southeast-1:123456789012:table/lesson12-13-dev-users\"}]}"
    }
  }
  assert {
    condition = (
      aws_lambda_function.this.runtime == "python3.13" &&
      aws_lambda_function.this.handler == "handler.lambda_handler" &&
      aws_lambda_function.this.architectures == tolist(["arm64"]) &&
      aws_lambda_function.this.memory_size == 1024 &&
      aws_lambda_function.this.timeout == 10 &&
      aws_lambda_function.this.environment[0].variables["TABLE_NAME"] == "lesson12-13-dev-users" &&
      aws_lambda_function.this.logging_config[0].log_format == "JSON" &&
      aws_iam_role.this.name == "lesson12-13-dev-lambda" &&
      aws_cloudwatch_log_group.this.retention_in_days == 7 &&
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com" &&
      aws_iam_role_policy_attachment.logs.policy_arn == "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    )
    error_message = "The function must use the given runtime/handler/memory/env, log as JSON with retention, and trust only Lambda."
  }
  assert {
    condition = (
      keys(aws_iam_role_policy.inline) == ["users-table-read"] &&
      jsondecode(aws_iam_role_policy.inline["users-table-read"].policy).Statement[0].Action == ["dynamodb:GetItem", "dynamodb:Scan"]
    )
    error_message = "Each inline_policies entry must become one role policy named by its key, unchanged."
  }
}

run "api_gateway_module" {
  command = apply
  module {
    source = "../../modules/api-gateway"
  }
  variables {
    name                 = "lesson12-13-dev"
    lambda_function_name = "lesson12-13-dev"
    lambda_invoke_arn    = "arn:aws:apigateway:ap-southeast-1:lambda:path/2015-03-31/functions/arn:aws:lambda:ap-southeast-1:123456789012:function:lesson12-13-dev/invocations"
    routes               = ["GET /users", "GET /users/{id}"]
  }
  assert {
    condition = (
      aws_apigatewayv2_api.this.protocol_type == "HTTP" &&
      aws_apigatewayv2_integration.lambda.integration_type == "AWS_PROXY" &&
      aws_apigatewayv2_integration.lambda.payload_format_version == "2.0" &&
      toset(keys(aws_apigatewayv2_route.routes)) == toset(["GET /users", "GET /users/{id}"]) &&
      aws_apigatewayv2_stage.default.name == "$default" &&
      aws_apigatewayv2_stage.default.default_route_settings[0].throttling_rate_limit == 10 &&
      aws_lambda_permission.api.principal == "apigateway.amazonaws.com" &&
      aws_lambda_permission.api.source_arn == "arn:aws:execute-api:ap-southeast-1:123456789012:abc123/*/*"
    )
    error_message = "The API must proxy listed routes to Lambda with payload 2.0, throttle, and scope invoke permission to itself."
  }
}

run "reject_bad_route" {
  command = plan
  module {
    source = "../../modules/api-gateway"
  }
  variables {
    name                 = "lesson12-13-dev"
    lambda_function_name = "lesson12-13-dev"
    lambda_invoke_arn    = "arn:aws:apigateway:ap-southeast-1:lambda:path/x"
    routes               = ["/users"]
  }
  expect_failures = [var.routes]
}

run "reject_bad_lambda_inputs" {
  command = plan
  module {
    source = "../../modules/lambda-function"
  }
  variables {
    function_name      = "a-function-name-that-is-far-too-long-for-an-iam-role-name-x"
    package_path       = "../../../build/function.zip"
    runtime            = "python3.13"
    handler            = "handler.lambda_handler"
    memory_size        = 64
    timeout            = 901
    log_retention_days = 10
    log_format         = "XML"
    inline_policies    = { "bad name" = "{}" }
  }
  expect_failures = [var.function_name, var.memory_size, var.timeout, var.log_retention_days, var.log_format, var.inline_policies]
}

run "reject_bad_project" {
  command = plan
  variables {
    project = "Lesson_12_13"
  }
  expect_failures = [var.project]
}
