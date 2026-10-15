variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.aws_region)
    error_message = "Region must be us-east-1 or us-west-2."
  }
}

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

variable "instance_type" {
  description = "EC2 instance type for HPC nodes"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t2.micro", "t2.small", "t2.medium", "t3.micro", "t3.small", "t3.medium", "t3a.micro", "t3a.small", "t3a.medium", "t4g.micro", "t4g.small", "t4g.medium"], var.instance_type)
    error_message = "Instance type must be from the allowed list: t2/micro/small/medium, t3/micro/small/medium, t3a/micro/small/medium, t4g/micro/small/medium."
  }
}

variable "instance_count" {
  description = "Maximum number of EC2 instances"
  type        = number
  default     = 3

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 9
    error_message = "Instance count must be between 1 and 9 (sandbox limit)."
  }
}

variable "key_deletion_window" {
  description = "Number of days for KMS key deletion waiting period"
  type        = number
  default     = 30

  validation {
    condition     = var.key_deletion_window >= 7 && var.key_deletion_window <= 365
    error_message = "Key deletion window must be between 7 and 365 days."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones for subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "flow_logs_log_group_name" {
  description = "Deprecated; log group is session-scoped in module"
  type        = string
  default     = ""
}

variable "flow_logs_traffic_type" {
  description = "Type of traffic to log (ALL, ACCEPT, REJECT)"
  type        = string
  default     = "ALL"
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateway for private subnets"
  type        = bool
  default     = true
}

variable "enable_fsx" {
  description = "Enable FSx for Lustre scratch storage (smallest deployment)"
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway for all private subnets"
  type        = bool
  default     = true
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for remote execution"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "build_instance_type" {
  description = "EC2 instance type for Image Builder build instances (t3.medium recommended for compiling Slurm)"
  type        = string
  default     = "t3.medium"

  validation {
    condition     = contains(["t2.micro", "t2.small", "t2.medium", "t3.micro", "t3.small", "t3.medium", "t3a.micro", "t3a.small", "t3a.medium", "t4g.micro", "t4g.small", "t4g.medium"], var.build_instance_type)
    error_message = "Build instance type must be from the allowed list."
  }
}

variable "build_ami_on_apply" {
  description = "If true, terraform apply builds an HPC AMI via Image Builder (blocks 45–120 min). Prefer make ami-build."
  type        = bool
  default     = false
}

variable "slurm_version" {
  description = "Slurm version to install"
  type        = string
  default     = "23.02.4"
}

variable "initial_ami_id" {
  description = "Initial AMI ID for SSM parameter (empty for first build)"
  type        = string
  default     = ""
}

variable "image_termination_date" {
  description = "Termination date for Image Builder infrastructure configuration (empty for no automatic termination)"
  type        = string
  default     = ""
}

variable "enable_mariadb" {
  description = "Enable MariaDB RDS instance for slurmdbd"
  type        = bool
  default     = true
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

variable "ebs_volume_size" {
  description = "Size of EBS volume for instances in GB"
  type        = number
  default     = 50
}

variable "ebs_volume_type" {
  description = "Type of EBS volume"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "sc1", "st1"], var.ebs_volume_type)
    error_message = "EBS volume type must be one of: gp2, gp3, io1, io2, sc1, st1."
  }
}

variable "ebs_volume_iops" {
  description = "IOPS for EBS volume (only for io1/io2/gp3)"
  type        = number
  default     = 3000
}

variable "ebs_volume_throughput" {
  description = "Throughput for EBS volume (only for gp3)"
  type        = number
  default     = 125
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to login node"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_key_name" {
  description = "EC2 key pair name for SSH access to login/debug nodes"
  type        = string
  default     = ""
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

variable "create_monitoring" {
  type    = bool
  default = true
}
variable "create_alarms" {
  type    = bool
  default = true
}
variable "create_portal" {
  type    = bool
  default = true
}
variable "create_patch" {
  type    = bool
  default = true
}
variable "create_fis" {
  description = "Create FIS experiment templates (blocked by SCP in many sandboxes)"
  type        = bool
  default     = false
}
variable "enable_directory" {
  type    = bool
  default = false
}
variable "alarm_email" {
  type    = string
  default = ""
}

variable "controller_instance_type" {
  description = "Instance type for Slurm controller"
  type        = string
  default     = "t3.medium"
}
