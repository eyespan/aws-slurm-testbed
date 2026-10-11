# Controller module variables for HPC Platform Operations Test Bed

variable "project" {
  description = "Project name for tagging"
  type        = string
  default     = "hpc-testbed"
}

variable "env" {
  description = "Environment name for tagging"
  type        = string
  default     = "dev"
}

variable "session" {
  description = "Session identifier for tagging"
  type        = string
  default     = "default"
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Map of security group IDs from network module"
  type        = map(string)
}

variable "kms_key_arns" {
  description = "Map of KMS key ARNs from bootstrap module"
  type        = map(string)
}

variable "efs_file_system_id" {
  description = "ID of the EFS file system for Slurm state"
  type        = string
  default     = ""
}

variable "efs_mount_target_ids" {
  description = "List of EFS mount target IDs"
  type        = list(string)
  default     = []
}

variable "private_hosted_zone_id" {
  description = "ID of the Route 53 private hosted zone"
  type        = string
}

variable "private_hosted_zone_name" {
  description = "Name of the Route 53 private hosted zone"
  type        = string
  default     = "hpc.internal"
}

variable "slurm_version" {
  description = "Slurm version to install"
  type        = string
  default     = "23.02.4"
}

variable "controller_instance_type" {
  description = "EC2 instance type for controller node"
  type        = string
  default     = "t3.medium"

  validation {
    condition     = contains(["t2.micro", "t2.small", "t2.medium", "t3.micro", "t3.small", "t3.medium", "t3a.micro", "t3a.small", "t3a.medium", "t4g.micro", "t4g.small", "t4g.medium"], var.controller_instance_type)
    error_message = "Controller instance type must be from the allowed list."
  }
}

variable "debug_instance_type" {
  description = "EC2 instance type for debug node"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t2.micro", "t2.small", "t2.medium", "t3.micro", "t3.small", "t3.medium", "t3a.micro", "t3a.small", "t3a.medium", "t4g.micro", "t4g.small", "t4g.medium"], var.debug_instance_type)
    error_message = "Debug instance type must be from the allowed list."
  }
}

variable "ami_id" {
  description = "AMI ID for controller and compute nodes"
  type        = string
}

variable "enable_mariadb" {
  description = "Enable MariaDB RDS instance for slurmdbd"
  type        = bool
  default     = true
}

variable "create_mariadb_password_secret" {
  description = "Create MariaDB password in Secrets Manager"
  type        = bool
  default     = false
}

variable "mariadb_instance_class" {
  description = "RDS instance class for MariaDB"
  type        = string
  default     = "db.t4g.micro"
}

variable "mariadb_allocated_storage" {
  description = "Allocated storage for MariaDB in GB"
  type        = number
  default     = 20
}

variable "mariadb_username" {
  description = "Master username for MariaDB"
  type        = string
  default     = "slurm"
}

variable "mariadb_db_name" {
  description = "Database name for Slurm accounting"
  type        = string
  default     = "slurm_acct_db"
}

variable "mariadb_password" {
  description = "Master password for MariaDB"
  type        = string
  default     = "change_me"

  validation {
    condition     = length(var.mariadb_password) >= 8
    error_message = "MariaDB password must be at least 8 characters."
  }
}

variable "controller_ebs_volume_size" {
  description = "Size of EBS volume for controller in GB"
  type        = number
  default     = 50
}

variable "controller_ebs_volume_type" {
  description = "Type of EBS volume for controller"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "sc1", "st1"], var.controller_ebs_volume_type)
    error_message = "EBS volume type must be one of: gp2, gp3, io1, io2, sc1, st1."
  }
}

variable "controller_ebs_volume_iops" {
  description = "IOPS for EBS volume (only for io1/io2/gp3)"
  type        = number
  default     = 3000
}

variable "controller_ebs_volume_throughput" {
  description = "Throughput for EBS volume (only for gp3)"
  type        = number
  default     = 125
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for remote execution"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.aws_region)
    error_message = "Region must be us-east-1 or us-west-2."
  }
}

variable "slurm_state_dir" {
  description = "Directory for Slurm state files"
  type        = string
  default     = "/var/spool/slurmctld"
}
