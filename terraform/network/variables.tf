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

variable "enable_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "flow_logs_log_group_name" {
  description = "CloudWatch Logs log group name for VPC flow logs"
  type        = string
  default     = "/aws/vpc-flow-logs/hpc"
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

variable "single_nat_gateway" {
  description = "Use single NAT gateway for all private subnets"
  type        = bool
  default     = true
}
