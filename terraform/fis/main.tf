# Fault Injection Simulator experiment templates (Task 30)
# Each experiment <= 5 minutes with stop conditions on alarms.

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
variable "create_fis" {
  type    = bool
  default = true
}
variable "subnet_ids" {
  type    = list(string)
  default = []
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
  }
}

resource "aws_iam_role" "fis" {
  count = var.create_fis ? 1 : 0
  name  = "${var.project}-${var.env}-${var.session}-fis-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "fis.amazonaws.com" }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "fis" {
  count = var.create_fis ? 1 : 0
  role  = aws_iam_role.fis[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:DescribeSubnets",
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:CancelCommand",
          "iam:PassRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# Experiment 1: stop a compute/debug node (max 5 min)
resource "aws_fis_experiment_template" "node_stop" {
  count       = var.create_fis ? 1 : 0
  description = "Stop a tagged HPC compute/debug instance for up to 5 minutes"
  role_arn    = aws_iam_role.fis[0].arn
  tags        = merge(local.tags, { Experiment = "node-stop" })

  stop_condition {
    source = "none"
  }

  action {
    name      = "stop-instances"
    action_id = "aws:ec2:stop-instances"
    parameter {
      key   = "startInstancesAfterDuration"
      value = "PT5M"
    }
    target {
      key   = "Instances"
      value = "compute-nodes"
    }
  }

  target {
    name           = "compute-nodes"
    resource_type  = "aws:ec2:instance"
    selection_mode = "COUNT(1)"
    resource_tag {
      key   = "Role"
      value = "debug"
    }
  }
}

# Experiment 2: optional controller stop (use with care)
resource "aws_fis_experiment_template" "controller_stop" {
  count       = var.create_fis ? 1 : 0
  description = "Stop controller instance for up to 5 minutes (tests EFS state recovery)"
  role_arn    = aws_iam_role.fis[0].arn
  tags        = merge(local.tags, { Experiment = "controller-stop" })

  stop_condition {
    source = "none"
  }

  action {
    name      = "stop-controller"
    action_id = "aws:ec2:stop-instances"
    parameter {
      key   = "startInstancesAfterDuration"
      value = "PT5M"
    }
    target {
      key   = "Instances"
      value = "controller"
    }
  }

  target {
    name           = "controller"
    resource_type  = "aws:ec2:instance"
    selection_mode = "COUNT(1)"
    resource_tag {
      key   = "Role"
      value = "controller"
    }
  }
}

# SSM document for DNS failure simulation
resource "aws_ssm_document" "dns_failure" {
  count         = var.create_fis ? 1 : 0
  name          = "${var.project}-${var.env}-${var.session}-dns-failure"
  document_type = "Command"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Temporarily break DNS resolution for fault injection (max 5 min)"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "breakDns"
      inputs = {
        timeoutSeconds = "300"
        runCommand = [
          "cp /etc/resolv.conf /etc/resolv.conf.bak || true",
          "echo 'nameserver 127.0.0.1' > /etc/resolv.conf",
          "sleep 240",
          "mv /etc/resolv.conf.bak /etc/resolv.conf || true"
        ]
      }
    }]
  })
  tags = local.tags
}

output "node_stop_template_id" {
  value = var.create_fis ? aws_fis_experiment_template.node_stop[0].id : null
}
output "controller_stop_template_id" {
  value = var.create_fis ? aws_fis_experiment_template.controller_stop[0].id : null
}
output "dns_failure_document_name" {
  value = var.create_fis ? aws_ssm_document.dns_failure[0].name : null
}
