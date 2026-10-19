# Status portal ALB in front of login-node service + monitoring (Grafana/Prometheus) (Task 22)

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "project" { type = string }
variable "env" { type = string }
variable "session" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "login_instance_id" {
  type    = string
  default = ""
}
variable "login_private_ip" {
  type    = string
  default = ""
}
variable "create_portal" {
  type    = bool
  default = true
}
variable "attach_login" {
  description = "Attach login instance to target group (known at plan time)"
  type        = bool
  default     = true
}

# Monitoring integration
variable "monitoring_instance_id" {
  type    = string
  default = ""
}
variable "monitoring_security_group_id" {
  type    = string
  default = ""
}
variable "attach_monitoring" {
  description = "Attach monitoring instance to Grafana/Prometheus target groups"
  type        = bool
  default     = true
}

locals {
  tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
  }
}

resource "aws_security_group" "alb" {
  count       = var.create_portal ? 1 : 0
  name        = "${var.project}-${var.env}-${var.session}-portal-alb-sg"
  description = "ALB for status portal and monitoring UIs"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, { Name = "${var.project}-portal-alb-sg" })
}

# Allow ALB → monitoring Grafana (3000) and Prometheus (9090)
resource "aws_security_group_rule" "monitoring_grafana_from_alb" {
  #count                    = var.create_portal && var.monitoring_security_group_id != "" ? 1 : 0
  count = var.create_portal ? 1 : 0
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb[0].id
  security_group_id        = var.monitoring_security_group_id
  description              = "Grafana from portal ALB"
}

resource "aws_security_group_rule" "monitoring_prometheus_from_alb" {
  #count                    = var.create_portal && var.monitoring_security_group_id != "" ? 1 : 0
  count = var.create_portal ? 1 : 0
  type                     = "ingress"
  from_port                = 9090
  to_port                  = 9090
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb[0].id
  security_group_id        = var.monitoring_security_group_id
  description              = "Prometheus from portal ALB"
}

resource "aws_lb" "portal" {
  count              = var.create_portal ? 1 : 0
  name               = "${var.project}-${var.session}-portal"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = var.public_subnet_ids
  tags               = merge(local.tags, { Name = "${var.project}-portal-alb" })
}

# ---------------------------------------------------------------------------
# Target groups
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "portal" {
  count       = var.create_portal ? 1 : 0
  name        = "${var.project}-${var.session}-portal-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"
  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    matcher             = "200"
  }
  tags = local.tags
}

resource "aws_lb_target_group" "grafana" {
  count       = var.create_portal ? 1 : 0
  name        = "${var.project}-${var.session}-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"
  health_check {
    # Grafana runs with GF_SERVER_SERVE_FROM_SUB_PATH=true
    path                = "/grafana/api/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    matcher             = "200"
  }
  tags = merge(local.tags, { Service = "grafana" })
}

resource "aws_lb_target_group" "prometheus" {
  count       = var.create_portal ? 1 : 0
  name        = "${var.project}-${var.session}-prom-tg"
  port        = 9090
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"
  health_check {
    # Prometheus is started with --web.route-prefix=/prometheus
    path                = "/prometheus/-/healthy"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    matcher             = "200"
  }
  tags = merge(local.tags, { Service = "prometheus" })
}

resource "aws_lb_target_group_attachment" "login" {
  count            = var.create_portal && var.attach_login && var.login_instance_id != "" ? 1 : 0
  target_group_arn = aws_lb_target_group.portal[0].arn
  target_id        = var.login_instance_id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "grafana" {
  #count            = var.create_portal && var.attach_monitoring && var.monitoring_instance_id != "" ? 1 : 0
  count = var.create_portal && var.attach_monitoring ? 1 : 0
  target_group_arn = aws_lb_target_group.grafana[0].arn
  target_id        = var.monitoring_instance_id
  port             = 3000
}

resource "aws_lb_target_group_attachment" "prometheus" {
  #count            = var.create_portal && var.attach_monitoring && var.monitoring_instance_id != "" ? 1 : 0
  count = var.create_portal && var.attach_monitoring ? 1 : 0
  target_group_arn = aws_lb_target_group.prometheus[0].arn
  target_id        = var.monitoring_instance_id
  port             = 9090
}

# ---------------------------------------------------------------------------
# Listener + path-based rules
# ---------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  count             = var.create_portal ? 1 : 0
  load_balancer_arn = aws_lb.portal[0].arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.portal[0].arn
  }
}

# Higher priority = evaluated first
resource "aws_lb_listener_rule" "grafana" {
  count        = var.create_portal ? 1 : 0
  listener_arn = aws_lb_listener.http[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana[0].arn
  }

  condition {
    path_pattern {
      values = ["/grafana", "/grafana/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prometheus" {
  count        = var.create_portal ? 1 : 0
  listener_arn = aws_lb_listener.http[0].arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus[0].arn
  }

  condition {
    path_pattern {
      values = ["/prometheus", "/prometheus/*"]
    }
  }
}

# Prometheus does not natively serve under /prometheus. Optional path rewrite
# via fixed-response is not ideal; instead expose Prometheus at /prometheus/*
# only if --web.external-url is set. For simplicity we forward the path as-is
# and document that UI links may need /prometheus prefix stripped, OR users
# hit the private IP / SSM tunnel. Grafana is correctly configured for /grafana.

output "alb_dns_name" {
  value = var.create_portal ? aws_lb.portal[0].dns_name : null
}
output "portal_url" {
  value = var.create_portal ? "http://${aws_lb.portal[0].dns_name}/" : null
}
output "grafana_alb_url" {
  value = var.create_portal ? "http://${aws_lb.portal[0].dns_name}/grafana/" : null
}
output "prometheus_alb_url" {
  value = var.create_portal ? "http://${aws_lb.portal[0].dns_name}/prometheus/" : null
}
output "alb_security_group_id" {
  value = var.create_portal ? aws_security_group.alb[0].id : null
}
