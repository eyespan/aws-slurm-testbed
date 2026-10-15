# Patch Manager baseline + maintenance window for static nodes (Task 25)

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
variable "create_patch" {
  type    = bool
  default = true
}

locals {
  tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
  }
}

resource "aws_ssm_patch_baseline" "al2023" {
  count            = var.create_patch ? 1 : 0
  name             = "${var.project}-${var.env}-${var.session}-al2023"
  operating_system = "AMAZON_LINUX_2023"
  description      = "HPC static nodes patch baseline"

  approval_rule {
    approve_after_days = 7
    compliance_level   = "HIGH"
    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }
    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }
  tags = local.tags
}

resource "aws_ssm_default_patch_baseline" "al2023" {
  count            = var.create_patch ? 1 : 0
  baseline_id      = aws_ssm_patch_baseline.al2023[0].id
  operating_system = "AMAZON_LINUX_2023"
}

resource "aws_ssm_maintenance_window" "static_nodes" {
  count                      = var.create_patch ? 1 : 0
  name                       = "${var.project}-${var.env}-${var.session}-patch-window"
  schedule                   = "cron(0 3 ? * SUN *)"
  duration                   = 2
  cutoff                     = 1
  allow_unassociated_targets = true
  tags                       = local.tags
}

resource "aws_ssm_maintenance_window_target" "static" {
  count         = var.create_patch ? 1 : 0
  window_id     = aws_ssm_maintenance_window.static_nodes[0].id
  name          = "static-nodes"
  resource_type = "INSTANCE"
  targets {
    key    = "tag:Role"
    values = ["controller", "login", "monitoring"]
  }
}

resource "aws_ssm_maintenance_window_task" "patch" {
  count            = var.create_patch ? 1 : 0
  window_id        = aws_ssm_maintenance_window.static_nodes[0].id
  name             = "patch-static-nodes"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  max_concurrency  = "1"
  max_errors       = "0"
  service_role_arn = null # uses default service-linked role when available
  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.static[0].id]
  }
  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
    }
  }
}

output "patch_baseline_id" {
  value = var.create_patch ? aws_ssm_patch_baseline.al2023[0].id : null
}
output "maintenance_window_id" {
  value = var.create_patch ? aws_ssm_maintenance_window.static_nodes[0].id : null
}
