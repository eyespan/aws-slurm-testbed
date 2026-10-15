# Variables for the login node module
# Provisions login node (SSH access) and static debug node (interactive testing)

variable "project" {
  description = "Project name for tagging"
  type        = string
}

variable "env" {
  description = "Environment name for tagging"
  type        = string
}

variable "session" {
  description = "Session identifier for tagging"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (for SG rules allowing debug/controller ephemeral traffic)"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (login node placed in first)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs (debug node placed in first)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Map of security group IDs from the network module"
  type        = map(string)
  default     = {}
}

variable "kms_key_arns" {
  description = "Map of KMS key ARNs (expects key 'ebs')"
  type        = map(string)
}

variable "efs_file_system_id" {
  description = "EFS file system ID to mount"
  type        = string
}

variable "munge_key_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the munge key"
  type        = string
}

variable "private_hosted_zone_id" {
  description = "Route 53 private hosted zone ID for hpc.internal"
  type        = string
}

variable "private_hosted_zone_name" {
  description = "Route 53 private hosted zone name (e.g. hpc.internal)"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for login and debug nodes (from SSM or Image Builder)"
  type        = string
}

variable "controller_instance_ip" {
  description = "Private IP of the controller instance"
  type        = string
  default     = ""
}

variable "controller_iam_role_arn" {
  description = "ARN of the controller IAM role (unused but accepted for wiring)"
  type        = string
  default     = ""
}

variable "slurm_version" {
  description = "Pinned Slurm version"
  type        = string
  default     = "23.02.4"
}

variable "enable_mariadb" {
  description = "Whether MariaDB is enabled on the controller"
  type        = bool
  default     = true
}

variable "mariadb_endpoint" {
  description = "MariaDB endpoint (host:port or host)"
  type        = string
  default     = ""
}

variable "mariadb_port" {
  description = "MariaDB port"
  type        = string
  default     = "3306"
}

variable "mariadb_db_name" {
  description = "Slurm accounting database name"
  type        = string
  default     = "slurm_acct_db"
}

variable "mariadb_username" {
  description = "MariaDB username"
  type        = string
  default     = "slurm"
}

variable "ssh_key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  default     = ""
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to the login node"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ebs_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "ebs_volume_type" {
  description = "Root EBS volume type"
  type        = string
  default     = "gp3"
}

variable "ebs_volume_iops" {
  description = "Root EBS volume IOPS"
  type        = number
  default     = 3000
}

variable "ebs_volume_throughput" {
  description = "Root EBS volume throughput (MiB/s)"
  type        = number
  default     = 125
}

variable "create_login_node" {
  description = "Whether to create the login node"
  type        = bool
  default     = true
}

variable "create_debug_node" {
  description = "Whether to create the static debug node"
  type        = bool
  default     = true
}

variable "login_instance_type" {
  description = "Instance type for the login node"
  type        = string
  default     = "t3.small"

  validation {
    condition = contains([
      "t2.micro", "t2.small", "t2.medium",
      "t3.micro", "t3.small", "t3.medium",
      "t3a.micro", "t3a.small", "t3a.medium",
      "t4g.micro", "t4g.small", "t4g.medium"
    ], var.login_instance_type)
    error_message = "login_instance_type must be from the sandbox allow-list."
  }
}

variable "debug_instance_type" {
  description = "Instance type for the static debug node"
  type        = string
  default     = "t3.micro"

  validation {
    condition = contains([
      "t2.micro", "t2.small", "t2.medium",
      "t3.micro", "t3.small", "t3.medium",
      "t3a.micro", "t3a.small", "t3a.medium",
      "t4g.micro", "t4g.small", "t4g.medium"
    ], var.debug_instance_type)
    error_message = "debug_instance_type must be from the sandbox allow-list."
  }
}

variable "users_yaml_content" {
  description = "YAML content describing users to provision (name, uid, groups, ssh_keys)"
  type        = string
  default     = ""
}
