# CloudWatch alarms, SNS, canary support, probe Lambda (Tasks 20-21)

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

variable "project" { type = string }
variable "env" { type = string }
variable "session" { type = string }
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "create_alarms" {
  type    = bool
  default = true
}
variable "alarm_email" {
  type    = string
  default = ""
}
variable "efs_file_system_id" {
  type    = string
  default = ""
}

locals {
  tags_base = {
    Project = var.project
    Env     = var.env
    Session = var.session
  }
}

# SNS topic for all HPC alarms
resource "aws_sns_topic" "alarms" {
  count = var.create_alarms ? 1 : 0
  name  = "${var.project}-${var.env}-${var.session}-alarms"
  tags  = merge(local.tags_base, { Name = "${var.project}-alarms" })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.create_alarms && var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Helper: alarm with enforced metadata tags
# severity, sli, runbook — CI checks these

resource "aws_cloudwatch_metric_alarm" "scheduler_availability" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.project}-scheduler-availability"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "HealthCheckStatus"
  namespace           = "HPC/Slurm"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Scheduler probe failed (scontrol ping / port 6817)"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  ok_actions          = [aws_sns_topic.alarms[0].arn]
  tags = merge(local.tags_base, {
    severity = "SEV-1"
    sli      = "scheduler_availability"
    runbook  = "runbooks/controller-restart.md"
  })
}

resource "aws_cloudwatch_metric_alarm" "resume_failures" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.project}-resume-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "resume_failures"
  namespace           = "HPC/Slurm"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Node resume failures in last 5 minutes"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  tags = merge(local.tags_base, {
    severity = "SEV-2"
    sli      = "node_resume_failures"
    runbook  = "runbooks/node-down.md"
  })
}

resource "aws_cloudwatch_metric_alarm" "job_start_latency_warm" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.project}-job-start-latency-warm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "canary_job_start_seconds"
  namespace           = "HPC/Slurm"
  period              = 300
  statistic           = "Maximum"
  threshold           = 30
  alarm_description   = "Warm job start latency p95/max exceeded 30s (debug partition)"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  dimensions = {
    Partition = "debug"
  }
  tags = merge(local.tags_base, {
    severity = "SEV-3"
    sli      = "job_start_latency_warm"
    runbook  = "runbooks/stuck-job.md"
  })
}

resource "aws_cloudwatch_metric_alarm" "job_start_latency_cold" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.project}-job-start-latency-cold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "canary_job_start_seconds"
  namespace           = "HPC/Slurm"
  period              = 3600
  statistic           = "Maximum"
  threshold           = 360
  alarm_description   = "Cold job start latency (includes resume) exceeded 6 minutes"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  dimensions = {
    Partition = "std"
  }
  tags = merge(local.tags_base, {
    severity = "SEV-2"
    sli      = "job_start_latency_cold"
    runbook  = "runbooks/stuck-job.md"
  })
}

resource "aws_cloudwatch_metric_alarm" "efs_burst_credits" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.project}-efs-burst-credits"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 100000000000 # 100 GiB credits remaining
  alarm_description   = "EFS burst credits low"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  dimensions = {
    FileSystemId = var.efs_file_system_id
  }
  tags = merge(local.tags_base, {
    severity = "SEV-2"
    sli      = "storage_health"
    runbook  = "runbooks/connectivity-triage.md"
  })
}

resource "aws_cloudwatch_metric_alarm" "portal_availability" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.project}-portal-availability"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Status portal ALB has no healthy targets"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  tags = merge(local.tags_base, {
    severity = "SEV-2"
    sli      = "login_portal_availability"
    runbook  = "runbooks/controller-restart.md"
  })
}

# Probe Lambda — port / health checks (Task 20)
data "archive_file" "probe" {
  count       = var.create_alarms ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/probe.zip"
  source {
    content  = <<-PY
import json, os, socket, time, urllib.request
import boto3

def check_tcp(host, port, timeout=5):
    try:
        s = socket.create_connection((host, port), timeout=timeout)
        s.close()
        return True
    except OSError:
        return False

def put_metric(name, value, dims=None):
    cw = boto3.client("cloudwatch")
    md = {"MetricName": name, "Value": float(value), "Unit": "None",
          "Dimensions": [{"Name": k, "Value": v} for k, v in (dims or {}).items()]}
    cw.put_metric_data(Namespace="HPC/Slurm", MetricData=[md])

def handler(event, context):
    host = os.environ.get("CONTROLLER_HOST", "127.0.0.1")
    portal = os.environ.get("PORTAL_URL", "")
    ok_tcp = check_tcp(host, 6817)
    put_metric("HealthCheckStatus", 1 if ok_tcp else 0, {"Target": "slurmctld"})
    portal_ok = True
    if portal:
        try:
            urllib.request.urlopen(portal + "/healthz", timeout=5)
        except Exception:
            portal_ok = False
        put_metric("HealthCheckStatus", 1 if portal_ok else 0, {"Target": "portal"})
    return {"statusCode": 200, "body": json.dumps({"slurmctld": ok_tcp, "portal": portal_ok})}
PY
    filename = "probe.py"
  }
}

resource "aws_iam_role" "probe" {
  count = var.create_alarms ? 1 : 0
  name  = "${var.project}-${var.env}-${var.session}-probe-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "probe" {
  count = var.create_alarms ? 1 : 0
  role  = aws_iam_role.probe[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData", "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "probe" {
  count            = var.create_alarms ? 1 : 0
  function_name    = "${var.project}-${var.env}-${var.session}-probe"
  role             = aws_iam_role.probe[0].arn
  handler          = "probe.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.probe[0].output_path
  source_code_hash = data.archive_file.probe[0].output_base64sha256
  timeout          = 30
  environment {
    variables = {
      CONTROLLER_HOST = "controller.hpc.internal"
      PORTAL_URL      = ""
    }
  }
  tags = local.tags_base
}

resource "aws_cloudwatch_event_rule" "probe_schedule" {
  count               = var.create_alarms ? 1 : 0
  name                = "${var.project}-probe-every-minute"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "probe" {
  count     = var.create_alarms ? 1 : 0
  rule      = aws_cloudwatch_event_rule.probe_schedule[0].name
  target_id = "probe"
  arn       = aws_lambda_function.probe[0].arn
}

resource "aws_lambda_permission" "probe_events" {
  count         = var.create_alarms ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.probe[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.probe_schedule[0].arn
}

output "sns_topic_arn" {
  value = var.create_alarms ? aws_sns_topic.alarms[0].arn : null
}
output "probe_lambda_arn" {
  value = var.create_alarms ? aws_lambda_function.probe[0].arn : null
}
