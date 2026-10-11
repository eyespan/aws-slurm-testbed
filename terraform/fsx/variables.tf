variable "vpc_id" {
  description = "ID of the VPC where FSx will be deployed"
  type        = string
}

variable "fsx_subnet_id" {
  description = "Subnet ID for FSx deployment (should be in a private subnet)"
  type        = string
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

variable "enable_fsx" {
  description = "Enable FSx for Lustre storage"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for FSx encryption"
  type        = string
  default     = ""
}
