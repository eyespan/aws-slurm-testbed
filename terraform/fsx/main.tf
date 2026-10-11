# FSx for Lustre module for HPC Platform Operations Test Bed
# Implements smallest scratch deployment with optional enabling via enable_fsx flag

# =============================================================================
# FSx for Lustre File System
# =============================================================================

resource "aws_fsx_lustre_file_system" "scratch" {
  count = var.enable_fsx ? 1 : 0

  deployment_type  = "SCRATCH_2"
  storage_capacity = 1200 # Smallest allowed for Scratch_2 (1200 GB)
  log_configuration {
    level = "WARN_ONLY"
  }
  subnet_ids         = [var.fsx_subnet_id]
  security_group_ids = [var.security_group_ids["fsx"]]
  storage_type       = "SSD"

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-fsx-scratch"
    Project = var.project
    Env     = var.env
    Session = var.session
  }
}

# =============================================================================
# Mount Target (for documentation - actual mount is done via user data/ansible)
# =============================================================================

# Note: FSx mount is typically done via instance user data or configuration management
# The mount point is /scratch as specified in requirements

# =============================================================================
# CloudWatch Alarms for FSx
# =============================================================================

data "aws_region" "current" {}

# Free Storage Space Alarm
resource "aws_cloudwatch_metric_alarm" "fsx_free_storage" {
  count = var.enable_fsx ? 1 : 0

  alarm_name          = "${var.project}-${var.env}-${var.session}-fsx-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageCapacity"
  namespace           = "AWS/FSx"
  period              = 300
  statistic           = "Average"
  threshold           = 107374182400 # 100 GB
  alarm_description   = "FSx free storage capacity is low"
  dimensions = {
    FileSystemId = aws_fsx_lustre_file_system.scratch[0].id
  }
  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.name}:ec2:notify"
  ]

  tags = {
    Name     = "${var.project}-${var.env}-${var.session}-fsx-free-storage"
    severity = "warning"
    sli      = "storage_health"
    runbook  = "https://github.com/yohannesm/cguru/hpc-testbed/runbooks/storage-issues.md"
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "file_system_id" {
  description = "ID of the FSx for Lustre file system"
  value       = var.enable_fsx ? aws_fsx_lustre_file_system.scratch[0].id : null
}

output "file_system_arn" {
  description = "ARN of the FSx for Lustre file system"
  value       = var.enable_fsx ? aws_fsx_lustre_file_system.scratch[0].arn : null
}

output "dns_name" {
  description = "DNS name of the FSx file system"
  value       = var.enable_fsx ? aws_fsx_lustre_file_system.scratch[0].dns_name : null
}

output "mount_name" {
  description = "Mount name of the FSx file system"
  value       = var.enable_fsx ? aws_fsx_lustre_file_system.scratch[0].mount_name : null
}

output "free_storage_capacity_alarm_name" {
  description = "Name of the free storage capacity alarm"
  value       = var.enable_fsx ? aws_cloudwatch_metric_alarm.fsx_free_storage[0].alarm_name : null
}
