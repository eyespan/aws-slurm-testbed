variable "aws_region" {
  description = "AWS region for Image Builder resources"
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

variable "component_version" {
  description = "Version for Image Builder components (bump when component YAML changes)"
  type        = string
  default     = "1.0.6"
}

variable "recipe_version" {
  description = "Version for Image Builder recipe (must bump when components change)"
  type        = string
  default     = "1.0.6"
}

variable "build_instance_type" {
  description = "Instance type for Image Builder builds (t3.medium recommended; Slurm compile needs RAM)"
  type        = string
  default     = "t3.medium"

  validation {
    condition     = contains(["t2.micro", "t2.small", "t2.medium", "t3.micro", "t3.small", "t3.medium", "t3a.micro", "t3a.small", "t3a.medium", "t4g.micro", "t4g.small", "t4g.medium"], var.build_instance_type)
    error_message = "Build instance type must be from the allowed list: t2/micro/small/medium, t3/micro/small/medium, t3a/micro/small/medium, t4g/micro/small/medium."
  }
}

variable "subnet_id" {
  description = "Subnet ID for Image Builder builds"
  type        = string
  default     = ""
}

variable "security_group_id" {
  description = "Security group ID for Image Builder builds"
  type        = string
  default     = ""
}

variable "log_bucket_name" {
  description = "S3 bucket name for Image Builder logs"
  type        = string
  default     = ""
}

variable "log_bucket_kms_key_arn" {
  description = "KMS key ARN encrypting the log bucket (SSE-KMS). Required for Image Builder PutObject."
  type        = string
  default     = ""
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

variable "initial_ami_id" {
  description = "Initial AMI ID for SSM parameter"
  type        = string
  default     = ""
}

variable "termination_date" {
  description = "Termination date for infrastructure configuration"
  type        = string
  default     = ""
}

variable "build_ami_on_apply" {
  description = "If true, terraform apply builds an AMI via Image Builder (blocks 45–120 min). Prefer make ami-build for on-demand builds."
  type        = bool
  default     = false
}
