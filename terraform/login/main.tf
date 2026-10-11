# Main Terraform configuration for login node module
# Provisions login node (SSH access) and debug node (interactive testing)

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = var.project
      Env     = var.env
      Session = var.session
    }
  }
}

# =============================================================================
# Module Outputs
# =============================================================================

output "login_node_instance_id" {
  description = "ID of the login node instance"
  value       = var.create_login_node ? aws_instance.login_node[0].id : null
}

output "login_node_instance_private_ip" {
  description = "Private IP of the login node"
  value       = var.create_login_node ? aws_instance.login_node[0].private_ip : null
}

output "login_node_instance_public_ip" {
  description = "Public IP of the login node (for SSH access)"
  value       = var.create_login_node ? aws_instance.login_node[0].public_ip : null
}

output "login_node_instance_dns" {
  description = "DNS name of the login node"
  value       = var.create_login_node ? aws_instance.login_node[0].public_dns : null
}

output "login_node_security_group_id" {
  description = "ID of the login node security group"
  value       = var.create_login_node ? aws_security_group.login_node[0].id : null
}

output "login_node_iam_role_arn" {
  description = "ARN of the login node IAM role"
  value       = var.create_login_node ? aws_iam_role.login_node[0].arn : null
}

output "debug_node_instance_id" {
  description = "ID of the debug node instance"
  value       = var.create_debug_node ? aws_instance.debug_node[0].id : null
}

output "debug_node_instance_private_ip" {
  description = "Private IP of the debug node"
  value       = var.create_debug_node ? aws_instance.debug_node[0].private_ip : null
}

output "debug_node_instance_dns" {
  description = "DNS name of the debug node"
  value       = var.create_debug_node ? aws_instance.debug_node[0].private_dns : null
}

output "debug_node_security_group_id" {
  description = "ID of the debug node security group"
  value       = var.create_debug_node ? aws_security_group.debug_node[0].id : null
}

output "debug_node_iam_role_arn" {
  description = "ARN of the debug node IAM role"
  value       = var.create_debug_node ? aws_iam_role.debug_node[0].arn : null
}

# =============================================================================
# Configuration Outputs
# =============================================================================

output "login_node_configuration" {
  description = "Login node configuration details"
  value = var.create_login_node ? {
    instance_id          = aws_instance.login_node[0].id
    instance_private_ip  = aws_instance.login_node[0].private_ip
    instance_public_ip   = aws_instance.login_node[0].public_ip
    instance_type        = var.login_instance_type
    security_group_id    = aws_security_group.login_node[0].id
    iam_role_arn         = aws_iam_role.login_node[0].arn
    ssh_key_name         = var.ssh_key_name
    allowed_ssh_cidrs    = var.allowed_ssh_cidr_blocks
    efs_mount_path       = "/shared/slurm-state"
    slurm_partition      = "debug"
  } : null
}

output "debug_node_configuration" {
  description = "Debug node configuration details"
  value = var.create_debug_node ? {
    instance_id         = aws_instance.debug_node[0].id
    instance_private_ip = aws_instance.debug_node[0].private_ip
    instance_type       = var.debug_instance_type
    security_group_id   = aws_security_group.debug_node[0].id
    iam_role_arn        = aws_iam_role.debug_node[0].arn
    slurm_partition     = "debug"
    is_static           = true
  } : null
}

output "node_access_info" {
  description = "Access information for login and debug nodes"
  value = {
    login_ssh_command = var.create_login_node ? "ssh -i ~/.ssh/${var.ssh_key_name} ec2-user@${aws_instance.login_node[0].public_ip}" : null
    debug_ssh_command = var.create_debug_node ? "ssh -i ~/.ssh/${var.ssh_key_name} ec2-user@${aws_instance.debug_node[0].private_ip}" : null
  }
}
