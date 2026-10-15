# Status portal ALB in front of login-node service (Task 22)

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
  description = "ALB for status portal"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, { Name = "${var.project}-portal-alb-sg" })
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

resource "aws_lb_target_group_attachment" "login" {
  count            = var.create_portal && var.attach_login ? 1 : 0
  target_group_arn = aws_lb_target_group.portal[0].arn
  target_id        = var.login_instance_id
  port             = 8080
}

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

output "alb_dns_name" {
  value = var.create_portal ? aws_lb.portal[0].dns_name : null
}
output "portal_url" {
  value = var.create_portal ? "http://${aws_lb.portal[0].dns_name}/" : null
}
