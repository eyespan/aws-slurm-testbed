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
