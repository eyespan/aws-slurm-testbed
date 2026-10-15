# Storage module for HPC Platform Operations Test Bed
# Implements EFS file system with encryption, mount targets, access points, and CloudWatch alarms

# =============================================================================
# EFS File System
# =============================================================================

resource "aws_efs_file_system" "hpc" {
  count = var.enable_efs ? 1 : 0

  creation_token = "${var.project}-${var.env}-${var.session}-efs"
  encrypted      = true
  kms_key_id     = var.kms_key_arn != "" ? var.kms_key_arn : null

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-efs"
    Project = var.project
    Env     = var.env
    Session = var.session
  }
}

# =============================================================================
# EFS Mount Targets (one per AZ)
# =============================================================================

resource "aws_efs_mount_target" "hpc" {
  for_each = {
    for idx, subnet_id in var.private_subnet_ids : idx => subnet_id
    if var.enable_efs
  }

  file_system_id  = aws_efs_file_system.hpc[0].id
  subnet_id       = each.value
  security_groups = [var.security_group_ids["efs"]]
}

# =============================================================================
# EFS Access Points
# =============================================================================

# Access point for /shared
resource "aws_efs_access_point" "shared" {
  count = var.enable_efs ? 1 : 0

  file_system_id = aws_efs_file_system.hpc[0].id
  root_directory {
    path = "/shared"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0755"
    }
  }
  tags = {
    Name = "${var.project}-${var.env}-${var.session}-efs-shared-ap"
  }
}

# Access point for /home
resource "aws_efs_access_point" "home" {
  count = var.enable_efs ? 1 : 0

  file_system_id = aws_efs_file_system.hpc[0].id
  root_directory {
    path = "/home"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0755"
    }
  }
  tags = {
    Name = "${var.project}-${var.env}-${var.session}-efs-home-ap"
  }
}

# =============================================================================
# CloudWatch Alarms for EFS
# =============================================================================

data "aws_region" "current" {}

# Burst Credit Balance Alarm
resource "aws_cloudwatch_metric_alarm" "efs_burst_credits" {
  count = var.enable_efs ? 1 : 0

  alarm_name          = "${var.project}-${var.env}-${var.session}-efs-burst-credits"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000000
  alarm_description   = "EFS burst credit balance is low"
  dimensions = {
    FileSystemId = aws_efs_file_system.hpc[0].id
  }
tags = {
    Name     = "${var.project}-${var.env}-${var.session}-efs-burst-credits"
    severity = "warning"
    sli      = "storage_health"
    runbook  = "https://github.com/yohannesm/cguru/hpc-testbed/runbooks/storage-issues.md"
  }
}

# File System utilization Alarm
resource "aws_cloudwatch_metric_alarm" "efs_storage_utilization" {
  count = var.enable_efs ? 1 : 0

  alarm_name          = "${var.project}-${var.env}-${var.session}-efs-storage-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TotalFileSystemBytes"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 858993459200
  alarm_description   = "EFS storage utilization is above 85%"
  dimensions = {
    FileSystemId = aws_efs_file_system.hpc[0].id
  }
tags = {
    Name     = "${var.project}-${var.env}-${var.session}-efs-storage-utilization"
    severity = "warning"
    sli      = "storage_health"
    runbook  = "https://github.com/yohannesm/cguru/hpc-testbed/runbooks/storage-issues.md"
  }
}

# Permitted Throughput Alarm
resource "aws_cloudwatch_metric_alarm" "efs_throughput" {
  count = var.enable_efs ? 1 : 0

  alarm_name          = "${var.project}-${var.env}-${var.session}-efs-throughput"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "PermittedThroughput"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 104857600
  alarm_description   = "EFS permitted throughput is low"
  dimensions = {
    FileSystemId = aws_efs_file_system.hpc[0].id
  }
tags = {
    Name     = "${var.project}-${var.env}-${var.session}-efs-throughput"
    severity = "warning"
    sli      = "storage_health"
    runbook  = "https://github.com/yohannesm/cguru/hpc-testbed/runbooks/storage-issues.md"
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "file_system_id" {
  description = "ID of the EFS file system"
  value       = var.enable_efs ? aws_efs_file_system.hpc[0].id : null
}

output "file_system_arn" {
  description = "ARN of the EFS file system"
  value       = var.enable_efs ? aws_efs_file_system.hpc[0].arn : null
}

output "mount_target_ids" {
  description = "IDs of EFS mount targets"
  value       = [for mt in aws_efs_mount_target.hpc : mt.id]
}

output "shared_access_point_id" {
  description = "ID of the shared access point"
  value       = var.enable_efs ? aws_efs_access_point.shared[0].id : null
}

output "home_access_point_id" {
  description = "ID of the home access point"
  value       = var.enable_efs ? aws_efs_access_point.home[0].id : null
}

output "shared_access_point_arn" {
  description = "ARN of the shared access point"
  value       = var.enable_efs ? aws_efs_access_point.shared[0].arn : null
}

output "home_access_point_arn" {
  description = "ARN of the home access point"
  value       = var.enable_efs ? aws_efs_access_point.home[0].arn : null
}

output "burst_credits_alarm_name" {
  description = "Name of the burst credits alarm"
  value       = var.enable_efs ? aws_cloudwatch_metric_alarm.efs_burst_credits[0].alarm_name : null
}

output "storage_utilization_alarm_name" {
  description = "Name of the storage utilization alarm"
  value       = var.enable_efs ? aws_cloudwatch_metric_alarm.efs_storage_utilization[0].alarm_name : null
}

output "throughput_alarm_name" {
  description = "Name of the throughput alarm"
  value       = var.enable_efs ? aws_cloudwatch_metric_alarm.efs_throughput[0].alarm_name : null
}
