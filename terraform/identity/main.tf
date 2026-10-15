# Optional Simple AD + SSSD (Task 26). Default disabled; local YAML users are the fallback.

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "project" { type = string }
variable "env" { type = string }
variable "session" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "enable_directory" {
  type    = bool
  default = false
}
variable "directory_password" {
  type      = string
  default   = "ChangeMe-HpcDir1!"
  sensitive = true
}

locals {
  tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
  }
}

resource "aws_directory_service_directory" "simple_ad" {
  count    = var.enable_directory ? 1 : 0
  name     = "hpc.internal.ad"
  password = var.directory_password
  size     = "Small"
  type     = "SimpleAD"

  vpc_settings {
    vpc_id     = var.vpc_id
    subnet_ids = slice(var.private_subnet_ids, 0, min(2, length(var.private_subnet_ids)))
  }

  tags = merge(local.tags, { Name = "${var.project}-simple-ad" })
}

output "directory_id" {
  value = var.enable_directory ? aws_directory_service_directory.simple_ad[0].id : null
}
output "directory_dns_ip_addresses" {
  value = var.enable_directory ? aws_directory_service_directory.simple_ad[0].dns_ip_addresses : null
}
output "note" {
  value = var.enable_directory ? "Simple AD enabled — configure SSSD on nodes" : "Directory disabled; using config/users/users.yaml local users (fallback)"
}
