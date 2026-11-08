# Mocked AWS: no credentials or real resources.
mock_provider "aws" {
  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      api_endpoint  = "https://abc123.execute-api.ap-southeast-1.amazonaws.com"
      execution_arn = "arn:aws:execute-api:ap-southeast-1:111111111111:abc123"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:ap-southeast-1:111111111111:log-group:/aws/apigateway/lesson14-dev"
    }
  }
}

variables {
  name                       = "lesson14-dev"
  vpc_link_subnet_ids        = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  vpc_link_security_group_id = "sg-0123456789abcdef0"
  listener_arn               = "arn:aws:elasticloadbalancing:ap-southeast-1:111111111111:listener/app/l14-dev/0123456789abcdef/0123456789abcdef"
  jwt_issuer                 = "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_example"
  jwt_audience               = ["exampleclientid"]
  public_routes              = ["POST /api/users/register", "GET /api/products", "GET /api/products/{id}"]
  protected_routes           = ["GET /api/users/me", "ANY /api/cart/{proxy+}", "POST /api/orders"]
}

run "protected_routes_use_jwt" {
  command = apply # integration and authorizer IDs are only known after (mocked) apply

  assert {
    condition = alltrue([
      for r in var.protected_routes :
      aws_apigatewayv2_route.protected[r].authorization_type == "JWT" &&
      aws_apigatewayv2_route.protected[r].authorizer_id == aws_apigatewayv2_authorizer.jwt.id &&
      aws_apigatewayv2_route.protected[r].target == "integrations/${aws_apigatewayv2_integration.protected.id}"
    ])
    error_message = "Every protected route must use the JWT authorizer and the protected integration."
  }
  assert {
    condition = (
      aws_apigatewayv2_authorizer.jwt.authorizer_type == "JWT" &&
      aws_apigatewayv2_authorizer.jwt.identity_sources == toset(["$request.header.Authorization"]) &&
      one(aws_apigatewayv2_authorizer.jwt.jwt_configuration).issuer == var.jwt_issuer &&
      one(aws_apigatewayv2_authorizer.jwt.jwt_configuration).audience == toset(var.jwt_audience)
    )
    error_message = "The authorizer must validate the bearer token against the given issuer and audience."
  }
  assert {
    condition = alltrue([
      for i in [aws_apigatewayv2_integration.protected, aws_apigatewayv2_integration.public] :
      i.integration_type == "HTTP_PROXY" && i.integration_method == "ANY" && i.integration_uri == var.listener_arn &&
      i.connection_type == "VPC_LINK" && i.connection_id == aws_apigatewayv2_vpc_link.this.id && i.payload_format_version == "1.0"
    ])
    error_message = "Both integrations must proxy to the ALB listener through the VPC Link."
  }
  assert {
    condition = (
      output.api_endpoint == "https://abc123.execute-api.ap-southeast-1.amazonaws.com" &&
      output.api_host == "abc123.execute-api.ap-southeast-1.amazonaws.com"
    )
    error_message = "api_host must be api_endpoint without the https:// scheme."
  }
}

run "public_routes_have_no_authorizer" {
  command = apply

  assert {
    condition = alltrue([
      for r in var.public_routes :
      aws_apigatewayv2_route.public[r].authorization_type == "NONE" &&
      aws_apigatewayv2_route.public[r].target == "integrations/${aws_apigatewayv2_integration.public.id}"
    ])
    error_message = "Every public route must skip authorization and use the public integration."
  }
  assert {
    condition = (
      aws_apigatewayv2_integration.public.request_parameters == tomap({
        "remove:header.X-Customer-Sub"   = "''"
        "remove:header.X-Customer-Email" = "''"
      })
    )
    # An empty value is not a removal: the provider sends "" to delete a mapping, so AWS would keep none.
    error_message = "The public integration must strip client-supplied identity headers, each with the value \"''\"."
  }
}

run "identity_headers_overwritten_from_claims" {
  command = plan

  assert {
    condition = (
      aws_apigatewayv2_integration.protected.request_parameters["overwrite:header.X-Customer-Sub"] == "$context.authorizer.claims.sub" &&
      aws_apigatewayv2_integration.protected.request_parameters["overwrite:header.X-Customer-Email"] == "$context.authorizer.claims.email"
    )
    error_message = "The protected integration must overwrite identity headers from the JWT claims."
  }
  assert {
    condition = (
      aws_apigatewayv2_stage.default.name == "$default" && aws_apigatewayv2_stage.default.auto_deploy &&
      one(aws_apigatewayv2_stage.default.default_route_settings).throttling_burst_limit == 100 &&
      one(aws_apigatewayv2_stage.default.default_route_settings).throttling_rate_limit == 50 &&
      strcontains(one(aws_apigatewayv2_stage.default.access_log_settings).format, "$context.authorizer.error")
    )
    error_message = "The $default stage must auto-deploy with 100/50 throttling and log authorizer errors."
  }
}

run "reject_bad_route" {
  command = plan
  variables {
    public_routes    = ["FETCH /x"] # unknown method
    protected_routes = ["GET x"]    # path without leading slash
  }
  expect_failures = [var.public_routes, var.protected_routes]
}
