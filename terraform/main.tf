# Main Terraform configuration for HPC Platform Operations Test Bed
# Orchestrates the bootstrap, network, and storage modules

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

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
# Bootstrap Security Module
# =============================================================================

module "bootstrap" {
  source = "./bootstrap"

  aws_region          = var.aws_region
  project             = var.project
  env                 = var.env
  session             = var.session
  instance_type       = var.instance_type
  instance_count      = var.instance_count
  key_deletion_window = var.key_deletion_window
}

# =============================================================================
# Network Module
# =============================================================================

module "network" {
  source = "./network"

  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  project                  = var.project
  env                      = var.env
  session                  = var.session
  enable_flow_logs         = var.enable_flow_logs
  flow_logs_log_group_name = var.flow_logs_log_group_name
  flow_logs_traffic_type   = var.flow_logs_traffic_type
  enable_nat_gateway       = var.enable_nat_gateway
  single_nat_gateway       = var.single_nat_gateway
}

# =============================================================================
# Storage Module
# =============================================================================

module "storage" {
  source = "./storage"

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  security_group_ids = module.network.security_group_ids
  project            = var.project
  env                = var.env
  session            = var.session
  kms_key_arn        = module.bootstrap.kms_key_arns["efs"]
}

# =============================================================================
# Controller Module
# =============================================================================

module "controller" {
  source = "./controller"

  aws_region               = var.aws_region
  project                  = var.project
  env                      = var.env
  session                  = var.session
  vpc_id                   = module.network.vpc_id
  private_subnet_ids       = module.network.private_subnet_ids
  security_group_ids       = module.network.security_group_ids
  kms_key_arns             = module.bootstrap.kms_key_arns
  efs_file_system_id       = module.storage.file_system_id
  efs_mount_target_ids     = module.storage.mount_target_ids
  private_hosted_zone_id   = module.network.private_hosted_zone_id
  private_hosted_zone_name = module.network.private_hosted_zone_name
  slurm_version            = var.slurm_version
  ami_id                   = data.aws_ssm_parameter.ami_current.value
  ssh_private_key_path     = var.ssh_private_key_path
}

# Data source to get current AMI from SSM parameter
data "aws_ssm_parameter" "ami_current" {
  name = module.image_builder.ami_ssm_parameter_current
}

# =============================================================================
# FSx for Lustre Module
# =============================================================================

module "fsx" {
  source = "./fsx"

  vpc_id             = module.network.vpc_id
  fsx_subnet_id      = module.network.private_subnet_ids[0]
  security_group_ids = module.network.security_group_ids
  project            = var.project
  env                = var.env
  session            = var.session
  enable_fsx         = var.enable_fsx
  kms_key_arn        = module.bootstrap.kms_key_arns["fsx"]
}

# =============================================================================
# Image Builder Module
# =============================================================================

module "image_builder" {
  source = "./image-builder"

  aws_region          = var.aws_region
  project             = var.project
  env                 = var.env
  session             = var.session
  build_instance_type = var.build_instance_type
  subnet_id           = module.network.private_subnet_ids[0]
  security_group_id   = module.network.security_group_ids["compute"]
  log_bucket_name     = module.bootstrap.cloudtrail_logs_bucket_name
  key_deletion_window = var.key_deletion_window
  initial_ami_id      = var.initial_ami_id
  termination_date    = var.image_termination_date
}

# =============================================================================
# Outputs
# =============================================================================

output "kms_key_arns" {
  description = "ARNs of created KMS keys from bootstrap module"
  value       = module.bootstrap.kms_key_arns
}

output "cloudtrail_trail_arn" {
  description = "ARN of the CloudTrail trail from bootstrap module"
  value       = module.bootstrap.cloudtrail_trail_arn
}

output "cloudtrail_logs_bucket_name" {
  description = "Name of the CloudTrail logs S3 bucket from bootstrap module"
  value       = module.bootstrap.cloudtrail_logs_bucket_name
}

output "config_recorder_name" {
  description = "Name of the Config recorder from bootstrap module"
  value       = module.bootstrap.config_recorder_name
}

output "config_delivery_bucket_name" {
  description = "Name of the Config delivery S3 bucket from bootstrap module"
  value       = module.bootstrap.config_delivery_bucket_name
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector from bootstrap module"
  value       = module.bootstrap.guardduty_detector_id
}

output "security_hub_enabled" {
  description = "Whether Security Hub is enabled from bootstrap module"
  value       = module.bootstrap.security_hub_enabled
}

output "vpc_id" {
  description = "ID of the VPC from network module"
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC from network module"
  value       = module.network.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs of public subnets from network module"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of private subnets from network module"
  value       = module.network.private_subnet_ids
}

output "security_group_ids" {
  description = "IDs of created security groups from network module"
  value       = module.network.security_group_ids
}

output "s3_endpoint_id" {
  description = "ID of the S3 gateway endpoint from network module"
  value       = module.network.s3_endpoint_id
}

output "private_hosted_zone_id" {
  description = "ID of the Route 53 private hosted zone from network module"
  value       = module.network.private_hosted_zone_id
}

output "private_hosted_zone_name" {
  description = "Name of the Route 53 private hosted zone from network module"
  value       = module.network.private_hosted_zone_name
}

output "file_system_id" {
  description = "ID of the EFS file system from storage module"
  value       = module.storage.file_system_id
}

output "file_system_arn" {
  description = "ARN of the EFS file system from storage module"
  value       = module.storage.file_system_arn
}

output "mount_target_ids" {
  description = "IDs of EFS mount targets from storage module"
  value       = module.storage.mount_target_ids
}

output "shared_access_point_id" {
  description = "ID of the shared access point from storage module"
  value       = module.storage.shared_access_point_id
}

output "home_access_point_id" {
  description = "ID of the home access point from storage module"
  value       = module.storage.home_access_point_id
}

output "shared_access_point_arn" {
  description = "ARN of the shared access point from storage module"
  value       = module.storage.shared_access_point_arn
}

output "home_access_point_arn" {
  description = "ARN of the home access point from storage module"
  value       = module.storage.home_access_point_arn
}

output "burst_credits_alarm_name" {
  description = "Name of the burst credits alarm from storage module"
  value       = module.storage.burst_credits_alarm_name
}

output "storage_utilization_alarm_name" {
  description = "Name of the storage utilization alarm from storage module"
  value       = module.storage.storage_utilization_alarm_name
}

output "throughput_alarm_name" {
  description = "Name of the throughput alarm from storage module"
  value       = module.storage.throughput_alarm_name
}

output "fsx_file_system_id" {
  description = "ID of the FSx for Lustre file system"
  value       = module.fsx.file_system_id
}

output "fsx_dns_name" {
  description = "DNS name of the FSx file system"
  value       = module.fsx.dns_name
}

output "fsx_mount_name" {
  description = "Mount name of the FSx file system"
  value       = module.fsx.mount_name
}

output "fsx_free_storage_alarm_name" {
  description = "Name of the FSx free storage capacity alarm"
  value       = module.fsx.free_storage_capacity_alarm_name
}

# Image Builder Outputs
output "image_recipe_arn" {
  description = "ARN of the HPC compute image recipe"
  value       = module.image_builder.image_recipe_arn
}

output "image_pipeline_arn" {
  description = "ARN of the HPC compute image pipeline"
  value       = module.image_builder.image_pipeline_arn
}

output "infrastructure_configuration_arn" {
  description = "ARN of the infrastructure configuration"
  value       = module.image_builder.infrastructure_configuration_arn
}

output "ami_ssm_parameter_current" {
  description = "SSM parameter name for current AMI"
  value       = module.image_builder.ami_ssm_parameter_current
}

output "ami_ssm_parameter_previous" {
  description = "SSM parameter name for previous AMI"
  value       = module.image_builder.ami_ssm_parameter_previous
}

output "image_builder_role_arn" {
  description = "ARN of the Image Builder IAM role"
  value       = module.image_builder.image_builder_role_arn
}

output "kms_key_arn_ami" {
  description = "ARN of the KMS key for AMI encryption"
  value       = module.image_builder.kms_key_arn
}

# =============================================================================
# Controller Module Outputs
# =============================================================================

output "controller_instance_id" {
  description = "ID of the controller instance"
  value       = module.controller.controller_instance_id
}

output "controller_instance_private_ip" {
  description = "Private IP of the controller instance"
  value       = module.controller.controller_instance_private_ip
}

output "controller_instance_private_dns" {
  description = "Private DNS of the controller instance"
  value       = module.controller.controller_instance_private_dns
}

output "debug_instance_id" {
  description = "ID of the debug node instance"
  value       = module.controller.debug_instance_id
}

output "debug_instance_private_ip" {
  description = "Private IP of the debug node"
  value       = module.controller.debug_instance_private_ip
}

output "munge_key_secret_arn" {
  description = "ARN of the munge key secret"
  value       = module.controller.munge_key_secret_arn
}

output "mariadb_endpoint" {
  description = "Endpoint of the MariaDB instance"
  value       = module.controller.mariadb_endpoint
}

output "mariadb_port" {
  description = "Port of the MariaDB instance"
  value       = module.controller.mariadb_port
}
