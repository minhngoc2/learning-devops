resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  protocol_type = "HTTP"

  lifecycle {
    precondition {
      condition     = length(setintersection(var.public_routes, var.protected_routes)) == 0
      error_message = "A route key cannot be both public and protected."
    }
  }
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = var.name
  subnet_ids         = var.vpc_link_subnet_ids
  security_group_ids = [var.vpc_link_security_group_id]
}

# Rejects requests without a valid bearer token before they reach the integration.
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "${var.name}-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = var.jwt_issuer
    audience = var.jwt_audience
  }
}

# HTTP_PROXY through the VPC Link: requests reach the internal ALB listener unchanged except for the mapped headers.
# Services trust X-Customer-* only because these mappings overwrite (protected) or remove (public) any client copy.
resource "aws_apigatewayv2_integration" "protected" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = var.listener_arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.this.id
  payload_format_version = "1.0"

  request_parameters = {
    "overwrite:header.X-Customer-Sub"   = "$context.authorizer.claims.sub"
    "overwrite:header.X-Customer-Email" = "$context.authorizer.claims.email"
  }
}

resource "aws_apigatewayv2_integration" "public" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = var.listener_arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.this.id
  payload_format_version = "1.0"

  request_parameters = {
    "remove:header.X-Customer-Sub"   = ""
    "remove:header.X-Customer-Email" = ""
  }
}

resource "aws_apigatewayv2_route" "public" {
  for_each = toset(var.public_routes)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.public.id}"
}

resource "aws_apigatewayv2_route" "protected" {
  for_each = toset(var.protected_routes)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
  target             = "integrations/${aws_apigatewayv2_integration.protected.id}"
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.name}"
  retention_in_days = var.log_retention_days
}

# $default stage serves at the API root URL; auto_deploy publishes route changes immediately.
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      routeKey           = "$context.routeKey"
      status             = "$context.status"
      latencyMs          = "$context.responseLatency"
      integrationLatency = "$context.integrationLatency"
      integrationError   = "$context.integrationErrorMessage"
      authorizerError    = "$context.authorizer.error"
      sourceIp           = "$context.identity.sourceIp"
    })
  }
}
