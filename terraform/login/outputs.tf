# Login node module outputs

# =============================================================================
# Security Group Outputs
# =============================================================================

output "security_group_ids" {
  description = "Map of security group IDs"
  value = {
    login_node = var.create_login_node ? aws_security_group.login_node[0].id : null
    debug_node = var.create_debug_node ? aws_security_group.debug_node[0].id : null
  }
}
