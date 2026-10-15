# Controller module outputs

output "controller_instance_id" {
  description = "ID of the controller instance"
  value       = aws_instance.controller.id
}

output "controller_instance_private_ip" {
  description = "Private IP of the controller instance"
  value       = aws_instance.controller.private_ip
}

output "controller_instance_private_dns" {
  description = "Private DNS of the controller instance"
  value       = aws_instance.controller.private_dns
}

output "debug_instance_id" {
  description = "Deprecated - debug node lives in the login module"
  value       = null
}

output "debug_instance_private_ip" {
  description = "Deprecated - debug node lives in the login module"
  value       = null
}

output "munge_key_secret_arn" {
  description = "ARN of the munge key secret"
  value       = aws_secretsmanager_secret.munge_key.arn
}

output "iam_role_arn" {
  description = "ARN of the controller IAM role"
  value       = aws_iam_role.controller.arn
}

output "mariadb_endpoint" {
  description = "Endpoint of the MariaDB instance"
  value       = var.enable_mariadb ? aws_db_instance.mariadb[0].endpoint : null
}

output "mariadb_port" {
  description = "Port of the MariaDB instance"
  value       = var.enable_mariadb ? aws_db_instance.mariadb[0].port : null
}

output "mariadb_db_name" {
  description = "Database name for for Slurm accounting"
  value       = var.mariadb_db_name
}

output "controller_configuration" {
  description = "Controller node configuration details"
  value = {
    instance_id               = aws_instance.controller.id
    instance_private_ip       = aws_instance.controller.private_ip
    instance_type             = var.controller_instance_type
    debug_instance_id         = null
    debug_instance_private_ip = null
    munge_key_secret_arn      = aws_secretsmanager_secret.munge_key.arn
    slurm_version             = var.slurm_version
    slurm_state_dir           = var.slurm_state_dir
  }
}
