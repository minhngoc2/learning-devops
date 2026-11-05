resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Internal ALB for ${var.name}, reached through the API Gateway VPC Link"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from inside the VPC (VPC Link ENIs)"
}

resource "aws_vpc_security_group_egress_rule" "targets" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = var.container_port
  to_port           = var.container_port
  ip_protocol       = "tcp"
  description       = "Forward to ECS tasks on the container port inside the VPC"
}

resource "aws_lb" "this" {
  name               = var.name
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  drop_invalid_header_fields = true # strip headers with invalid names; the request is still forwarded
}

resource "aws_lb_target_group" "this" {
  for_each = var.services

  name                 = "${var.name}-${each.key}"
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  lifecycle {
    precondition {
      condition     = length("${var.name}-${each.key}") <= 32
      error_message = "Target group name ${var.name}-${each.key} exceeds 32 characters; shorten name or the service key."
    }
  }
}

# Anything that matches no rule (wrong path, or missing/wrong X-Origin-Verify) ends here.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = jsonencode({ error = "forbidden" })
      status_code  = "403"
    }
  }
}

# Both conditions must match: the path picks the service, the header proves the request came through CloudFront.
resource "aws_lb_listener_rule" "this" {
  for_each = var.services

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path_pattern]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_secret]
    }
  }
}
