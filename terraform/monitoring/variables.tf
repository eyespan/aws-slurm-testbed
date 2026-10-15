variable "project" { type = string }
variable "env" { type = string }
variable "session" { type = string }
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "security_group_ids" { type = map(string) }
variable "kms_key_arns" { type = map(string) }
variable "ami_id" { type = string }
variable "ssh_key_name" {
  type    = string
  default = ""
}
variable "instance_type" {
  type    = string
  default = "t3.medium"
  validation {
    condition = contains([
      "t2.micro", "t2.small", "t2.medium",
      "t3.micro", "t3.small", "t3.medium",
      "t3a.micro", "t3a.small", "t3a.medium",
      "t4g.micro", "t4g.small", "t4g.medium"
    ], var.instance_type)
    error_message = "Instance type must be from sandbox allow-list."
  }
}
variable "ebs_volume_size" {
  type    = number
  default = 40
}
variable "create_monitoring" {
  type    = bool
  default = true
}
variable "controller_private_ip" {
  type    = string
  default = ""
}
variable "private_hosted_zone_id" { type = string }
variable "private_hosted_zone_name" { type = string }
