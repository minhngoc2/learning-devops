# Mocked AWS: no credentials or real resources.
mock_provider "aws" {}

variables {
  name                 = "l14-dev"
  vpc_id               = "vpc-0123456789abcdef0"
  vpc_cidr             = "10.0.0.0/16"
  subnet_ids           = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  origin_verify_secret = "test-origin-secret"
  services = {
    user    = { path_pattern = "/api/users*", priority = 10 }
    product = { path_pattern = "/api/products*", priority = 20 }
    cart    = { path_pattern = "/api/cart*", priority = 30 }
  }
}

run "one_target_group_per_service" {
  command = plan

  assert {
    condition     = length(aws_lb_target_group.this) == 3 && length(aws_lb_listener_rule.this) == 3
    error_message = "Three services must give three target groups and three listener rules."
  }
  assert {
    condition = alltrue([
      for k, s in var.services : aws_lb_listener_rule.this[k].priority == s.priority
    ])
    error_message = "Each listener rule must use the priority given for its service."
  }
  assert {
    condition = alltrue([
      for k, s in var.services : one([
        for c in aws_lb_listener_rule.this[k].condition : one(c.path_pattern).values if length(c.path_pattern) > 0
      ]) == toset([s.path_pattern])
    ])
    error_message = "Each listener rule must match its service's path pattern."
  }
  assert {
    condition = alltrue([
      for k, tg in aws_lb_target_group.this :
      tg.name == "l14-dev-${k}" && tg.target_type == "ip" && tg.port == 8080 && tg.deregistration_delay == "30" &&
      tg.health_check[0].path == "/health" && tg.health_check[0].matcher == "200"
    ])
    error_message = "Target groups must be <name>-<service>, IP type on 8080, with /health checks."
  }
  assert {
    condition     = aws_lb.this.internal && aws_lb.this.drop_invalid_header_fields
    error_message = "The ALB must be internal and drop invalid header fields."
  }
  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.http.cidr_ipv4 == var.vpc_cidr && aws_vpc_security_group_ingress_rule.http.from_port == 80 &&
      aws_vpc_security_group_egress_rule.targets.cidr_ipv4 == var.vpc_cidr && aws_vpc_security_group_egress_rule.targets.to_port == 8080
    )
    error_message = "The ALB SG must allow port 80 in from the VPC and the container port out to the VPC only."
  }
}

run "rules_require_origin_header" {
  command = plan

  assert {
    condition = alltrue([
      for r in aws_lb_listener_rule.this : length([
        for c in r.condition : c if length(c.http_header) > 0 && one(c.http_header).http_header_name == "X-Origin-Verify"
      ]) == 1
    ])
    error_message = "Every listener rule must require the X-Origin-Verify header."
  }
  assert {
    condition = alltrue([
      for r in aws_lb_listener_rule.this : length(r.condition) == 2 && one(r.action).type == "forward"
    ])
    error_message = "Every rule must have exactly the path and header conditions and forward to its target group."
  }
}

run "direct_requests_get_403" {
  command = plan

  assert {
    condition     = aws_lb_listener.http.port == 80 && aws_lb_listener.http.protocol == "HTTP"
    error_message = "The listener must be HTTP on port 80."
  }
  assert {
    condition = (
      one(aws_lb_listener.http.default_action).type == "fixed-response" &&
      one(one(aws_lb_listener.http.default_action).fixed_response).status_code == "403" &&
      one(one(aws_lb_listener.http.default_action).fixed_response).content_type == "application/json"
    )
    error_message = "Requests matching no rule (no origin header) must get a 403 JSON fixed response."
  }
}

run "reject_bad_inputs" {
  command = plan
  variables {
    name       = "a-name-that-is-33-characters-long"
    subnet_ids = ["subnet-0123456789abcdef0"]
  }
  expect_failures = [var.name, var.subnet_ids]
}
