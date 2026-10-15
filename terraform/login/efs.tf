# EFS mount configuration for login and debug nodes

# =============================================================================
# EFS Mount Point Setup
# =============================================================================

# Mount EFS at /shared for both login and debug nodes
# This is handled via user_data scripts in ec2.tf
# This file exists for documentation and potential future expansion

# EFS mount point resource (using null_resource as a placeholder for mount point)
resource "null_resource" "efs_mount_points" {
  triggers = {
    login_node_id = var.create_login_node ? aws_instance.login_node[0].id : "none"
    debug_node_id = var.create_debug_node ? aws_instance.debug_node[0].id : "none"
    efs_id        = var.efs_file_system_id
  }
}

# =============================================================================
# CloudWatch Alarms for EFS (Login Node)
# =============================================================================

# EFS burst credit balance alarm for login node
resource "aws_cloudwatch_metric_alarm" "login_node_efs_burst_credits" {
  count = var.create_login_node ? 1 : 0

  alarm_name          = "${var.project}-${var.env}-${var.session}-login-efs-burst-credits"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000000
  alarm_description   = "EFS burst credit balance is low for login node"
  dimensions = {
    FileSystemId = var.efs_file_system_id
  }
tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
    Name    = "${var.project}-${var.env}-${var.session}-login-efs-burst-credits"
    severity = "warning"
    sli      = "storage_health"
  }
}

# EFS storage utilization alarm for login node
resource "aws_cloudwatch_metric_alarm" "login_node_efs_storage_utilization" {
  count = var.create_login_node ? 1 : 0

  alarm_name          = "${var.project}-${var.env}-${var.session}-login-efs-storage-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TotalFileSystemBytes"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 858993459200
  alarm_description   = "EFS storage utilization is above 85% for login node"
  dimensions = {
    FileSystemId = var.efs_file_system_id
  }
tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
    Name    = "${var.project}-${var.env}-${var.session}-login-efs-storage-utilization"
    severity = "warning"
    sli      = "storage_health"
  }
}

# EFS throughput alarm for login node
resource "aws_cloudwatch_metric_alarm" "login_node_efs_throughput" {
  count = var.create_login_node ? 1 : 0

  alarm_name          = "${var.project}-${var.env}-${var.session}-login-efs-throughput"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "PermittedThroughput"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 104857600
  alarm_description   = "EFS permitted throughput is low for login node"
  dimensions = {
    FileSystemId = var.efs_file_system_id
  }
tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
    Name    = "${var.project}-${var.env}-${var.session}-login-efs-throughput"
    severity = "warning"
    sli      = "storage_health"
  }
}

# =============================================================================
# Output: EFS Mount Information
# =============================================================================

output "efs_mount_info" {
  description = "EFS mount information for login and debug nodes"
  value = {
    file_system_id     = var.efs_file_system_id
    mount_target_count = length(var.private_subnet_ids)
    mount_path         = "/shared/slurm-state"
  }
}
