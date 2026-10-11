variable "vpc_id" {
  description = "ID of the VPC where EFS will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EFS mount targets"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Map of security group IDs from network module"
  type        = map(string)
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

variable "enable_efs" {
  description = "Enable EFS storage"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for EFS encryption"
  type        = string
  default     = ""
}

variable "enable_fsx" {
  description = "Enable FSx for Lustre storage"
  type        = bool
  default     = false
}
