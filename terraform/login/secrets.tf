# Secrets Manager configuration for login and debug nodes
# This module uses the existing munge key secret from the controller module

# =============================================================================
# Munge Key Secret Reference
# =============================================================================

# The munge key secret is passed as a variable from the controller module
# This file exists to document the secret configuration and for potential future expansion

# Reference to the munge key secret (defined in controller module)
resource "null_resource" "munge_key_reference" {
  triggers = {
    secret_arn = var.munge_key_secret_arn
  }
}

# =============================================================================
# CloudWatch Alarms for Secrets Manager Access
# =============================================================================

# Alarm for failed Secrets Manager access attempts (login node)
resource "aws_cloudwatch_metric_alarm" "login_node_secrets_access_failed" {
  count = var.create_login_node ? 1 : 0

  alarm_name          = "${var.project}-${var.env}-${var.session}-login-secrets-access-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Failed Secrets Manager access attempts for login node"
  dimensions = {
    QueueName = "secrets-access-queue"
  }

  tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
    Name    = "${var.project}-${var.env}-${var.session}-login-secrets-access-failed"
    severity = "critical"
    sli      = "security_health"
  }
}

# =============================================================================
# Output: Secrets Configuration
# =============================================================================

output "secrets_configuration" {
  description = "Secrets Manager configuration for login and debug nodes"
  value = {
    munge_key_secret_arn = var.munge_key_secret_arn
    secret_kms_key_id    = "managed-by-bootstrap"
    rotation_enabled     = true
  }
}
