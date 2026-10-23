# Mocked AWS: no credentials or real resources. Build build/bootstrap first (see quickstart).
mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/lesson13-dev-lambda"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:ap-southeast-1:123456789012:log-group:/aws/apigateway/lesson13-dev"
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
      invoke_arn = "arn:aws:apigateway:ap-southeast-1:lambda:path/2015-03-31/functions/arn:aws:lambda:ap-southeast-1:123456789012:function:lesson13-dev/invocations"
    }
  }
}

run "go_function" {
  command = apply

  assert {
    condition = (
      module.lambda_function.function_name == "lesson13-dev" &&
      output.api_url == "https://abc123.execute-api.ap-southeast-1.amazonaws.com"
    )
    error_message = "The dev root must name resources lesson13-dev and expose the API endpoint."
  }
}

run "lambda_function_module" {
  command = plan
  module {
    source = "../../modules/lambda-function"
  }
  variables {
    function_name = "lesson13-dev"
    package_path  = "../../../build/function.zip"
    runtime       = "provided.al2023"
    handler       = "bootstrap"
    environment_variables = {
      GREETING = "Hello"
    }
  }
  assert {
    condition = (
      aws_lambda_function.this.runtime == "provided.al2023" &&
      aws_lambda_function.this.handler == "bootstrap" &&
      aws_lambda_function.this.architectures == tolist(["arm64"]) &&
      aws_lambda_function.this.environment[0].variables["GREETING"] == "Hello" &&
      aws_lambda_function.this.memory_size == 128 &&
      aws_lambda_function.this.timeout == 10 &&
      aws_lambda_function.this.reserved_concurrent_executions == -1 &&
      aws_iam_role.this.name == "lesson13-dev-lambda" &&
      aws_cloudwatch_log_group.this.name == "/aws/lambda/lesson13-dev" &&
      aws_cloudwatch_log_group.this.retention_in_days == 7 &&
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com" &&
      aws_iam_role_policy_attachment.logs.policy_arn == "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    )
    error_message = "The function must use the given runtime/handler/arch, log with retention, and trust only Lambda."
  }
}

run "api_gateway_module" {
  command = apply
  module {
    source = "../../modules/api-gateway"
  }
  variables {
    name                 = "lesson13-dev"
    lambda_function_name = "lesson13-dev"
    lambda_invoke_arn    = "arn:aws:apigateway:ap-southeast-1:lambda:path/2015-03-31/functions/arn:aws:lambda:ap-southeast-1:123456789012:function:lesson13-dev/invocations"
    routes               = ["GET /hello", "POST /echo"]
  }
  assert {
    condition = (
      aws_apigatewayv2_api.this.protocol_type == "HTTP" &&
      aws_apigatewayv2_integration.lambda.integration_type == "AWS_PROXY" &&
      aws_apigatewayv2_integration.lambda.payload_format_version == "2.0" &&
      toset(keys(aws_apigatewayv2_route.routes)) == toset(["GET /hello", "POST /echo"]) &&
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
    name                 = "lesson13-dev"
    lambda_function_name = "lesson13-dev"
    lambda_invoke_arn    = "arn:aws:apigateway:ap-southeast-1:lambda:path/x"
    routes               = ["/hello"]
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
    runtime            = "provided.al2023"
    handler            = "bootstrap"
    memory_size        = 64
    timeout            = 901
    log_retention_days = 10
  }
  expect_failures = [var.function_name, var.memory_size, var.timeout, var.log_retention_days]
}

run "reject_bad_api_inputs" {
  command = plan
  module {
    source = "../../modules/api-gateway"
  }
  variables {
    name                   = "lesson13-dev"
    lambda_function_name   = "lesson13-dev"
    lambda_invoke_arn      = "arn:aws:apigateway:ap-southeast-1:lambda:path/x"
    routes                 = ["GET /hello"]
    throttling_rate_limit  = -1
    throttling_burst_limit = -1
    log_retention_days     = 2
  }
  expect_failures = [var.throttling_rate_limit, var.throttling_burst_limit, var.log_retention_days]
}

run "reject_bad_project" {
  command = plan
  variables {
    project = "Lesson_13"
  }
  expect_failures = [var.project]
}
