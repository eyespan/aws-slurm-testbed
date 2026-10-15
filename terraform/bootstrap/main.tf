# Bootstrap security module for HPC Platform Operations Test Bed
# Implements KMS keys, CloudTrail, Config, GuardDuty, and Security Hub

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}


# =============================================================================
# KMS Keys - Customer-managed keys with rotation enabled
# =============================================================================

# KMS key for EBS encryption
resource "aws_kms_key" "ebs" {
  description             = "Customer-managed KMS key for EBS encryption"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-ebs-key"
    Service = "EBS"
  }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.project}-${var.env}-${var.session}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

# KMS key for EFS encryption
resource "aws_kms_key" "efs" {
  description             = "Customer-managed KMS key for EFS encryption"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-efs-key"
    Service = "EFS"
  }
}

resource "aws_kms_alias" "efs" {
  name          = "alias/${var.project}-${var.env}-${var.session}-efs"
  target_key_id = aws_kms_key.efs.key_id
}

# KMS key for S3 encryption (used by CloudTrail logs)
resource "aws_kms_key" "s3" {
  description             = "Customer-managed KMS key for S3 log bucket encryption"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-s3-key"
    Service = "S3"
  }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project}-${var.env}-${var.session}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

# KMS key for CloudWatch Logs encryption
resource "aws_kms_key" "cloudwatch_logs" {
  description             = "Customer-managed KMS key for CloudWatch Logs encryption"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-cloudwatch-logs-key"
    Service = "CloudWatch Logs"
  }
}

resource "aws_kms_alias" "cloudwatch_logs" {
  name          = "alias/${var.project}-${var.env}-${var.session}-cloudwatch-logs"
  target_key_id = aws_kms_key.cloudwatch_logs.key_id
}

# KMS key for Secrets Manager (used by munge key and other secrets)
resource "aws_kms_key" "secrets_manager" {
  description             = "Customer-managed KMS key for Secrets Manager"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-secrets-key"
    Service = "Secrets Manager"
  }
}

resource "aws_kms_alias" "secrets_manager" {
  name          = "alias/${var.project}-${var.env}-${var.session}-secrets"
  target_key_id = aws_kms_key.secrets_manager.key_id
}

# KMS key for FSx for Lustre encryption
resource "aws_kms_key" "fsx" {
  description             = "Customer-managed KMS key for FSx for Lustre encryption"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-fsx-key"
    Service = "FSx"
  }
}

resource "aws_kms_alias" "fsx" {
  name          = "alias/${var.project}-${var.env}-${var.session}-fsx"
  target_key_id = aws_kms_key.fsx.key_id
}

# =============================================================================
# S3 Bucket for CloudTrail logs - Encrypted with KMS
# =============================================================================

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "${var.project}-${var.env}-${var.session}-cloudtrail-logs"
  force_destroy = true

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-cloudtrail-logs-bucket"
    Purpose = "CloudTrail log storage"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# =============================================================================
# CloudTrail - With log file validation
# =============================================================================

data "aws_partition" "current" {}
data "aws_region" "current" {}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-${var.env}-${var.session}-cloudtrail"
          }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail_logs.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-${var.env}-${var.session}-cloudtrail"
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.cloudtrail_logs,
    aws_s3_bucket_server_side_encryption_configuration.cloudtrail_logs,
  ]
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.project}-${var.env}-${var.session}-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  s3_key_prefix                 = "cloudtrail"
  enable_log_file_validation    = true
  is_multi_region_trail         = false # Multi-region off to stay in budget
  include_global_service_events = true

  # Avoid empty data_resource blocks that some accounts reject
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-cloudtrail"
  }
}

# =============================================================================
# AWS Config - Recorder and Rules
# =============================================================================

# S3 bucket for Config delivery (must exist before delivery channel)
resource "aws_s3_bucket" "config_delivery" {
  count = var.create_config_recorder ? 1 : 0

  bucket        = "${var.project}-${var.env}-${var.session}-config-delivery"
  force_destroy = true

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-config-delivery-bucket"
    Purpose = "Config delivery storage"
  }
}

resource "aws_s3_bucket_public_access_block" "config_delivery" {
  count = var.create_config_recorder ? 1 : 0

  bucket = aws_s3_bucket.config_delivery[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_delivery" {
  count = var.create_config_recorder ? 1 : 0

  bucket = aws_s3_bucket.config_delivery[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "config_delivery" {
  count = var.create_config_recorder ? 1 : 0

  bucket = aws_s3_bucket.config_delivery[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config_delivery[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AWSConfigBucketExistenceCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.config_delivery[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config_delivery[0].arn}/config-delivery/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.config_delivery,
    aws_s3_bucket_server_side_encryption_configuration.config_delivery,
  ]
}

# IAM Role for Config Recorder
resource "aws_iam_role" "config_recorder" {
  count = var.create_config_recorder ? 1 : 0

  name = "${var.project}-${var.env}-${var.session}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-config-role"
  }
}

# AWSConfigRole is deprecated/removed; use AWS_ConfigRole
resource "aws_iam_role_policy_attachment" "config_recorder" {
  count = var.create_config_recorder ? 1 : 0

  role       = aws_iam_role.config_recorder[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Inline policy so Config can write to the delivery bucket even if managed policy is thin
resource "aws_iam_role_policy" "config_recorder_s3" {
  count = var.create_config_recorder ? 1 : 0

  name = "${var.project}-${var.env}-${var.session}-config-s3"
  role = aws_iam_role.config_recorder[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.config_delivery[0].arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.config_delivery[0].arn}/*"
      }
    ]
  })
}

resource "aws_config_configuration_recorder" "main" {
  count = var.create_config_recorder ? 1 : 0

  name     = "${var.project}-${var.env}-${var.session}-config-recorder"
  role_arn = aws_iam_role.config_recorder[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [aws_iam_role_policy_attachment.config_recorder[0]]
}

resource "aws_config_delivery_channel" "main" {
  count = var.create_config_recorder ? 1 : 0

  name           = "${var.project}-${var.env}-${var.session}-config-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config_delivery[0].id
  s3_key_prefix  = "config-delivery"

  depends_on = [
    aws_config_configuration_recorder.main[0],
    aws_s3_bucket_policy.config_delivery[0],
  ]
}

resource "aws_config_configuration_recorder_status" "main" {
  count = var.create_config_recorder ? 1 : 0

  name       = aws_config_configuration_recorder.main[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main[0]]
}

# AWS Config Rules

# Rule: encrypted-volumes
resource "aws_config_config_rule" "encrypted_volumes" {
  count = var.create_config_recorder ? 1 : 0

  name = "encrypted-volumes"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# Rule: s3-bucket-public-read-prohibited
resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  count = var.create_config_recorder ? 1 : 0

  name = "s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# Rule: required-tags
resource "aws_config_config_rule" "required_tags" {
  count = var.create_config_recorder ? 1 : 0

  name = "required-tags"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key = "Project"
    tag2Key = "Env"
    tag3Key = "Session"
  })

  depends_on = [aws_config_configuration_recorder_status.main]
}

# Rule: iam-policy-no-statements-with-admin-access
resource "aws_config_config_rule" "iam_policy_no_statements_with_admin_access" {
  count = var.create_config_recorder ? 1 : 0

  name = "iam-policy-no-statements-with-admin-access"

  source {
    owner             = "AWS"
    source_identifier = "IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# Rule: cloudtrail-enabled
resource "aws_config_config_rule" "cloudtrail_enabled" {
  count = var.create_config_recorder ? 1 : 0

  name = "cloudtrail-enabled"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# =============================================================================
# GuardDuty - This account only
# =============================================================================

resource "aws_guardduty_detector" "main" {
  count = var.create_guardduty ? 1 : 0

  enable = true

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-guardduty"
  }
}

# =============================================================================
# Security Hub - This account only
# =============================================================================

# Enable Security Hub in this account only (sandbox has no Organizations admin rights)
resource "aws_securityhub_account" "main" {
  count = var.create_security_hub ? 1 : 0

  enable_default_standards  = true
  control_finding_generator = "SECURITY_CONTROL"

  depends_on = [aws_guardduty_detector.main[0]]
}

# =============================================================================
# Outputs
# =============================================================================

output "kms_key_arns" {
  description = "ARNs of created KMS keys"
  value = {
    ebs             = aws_kms_key.ebs.arn
    efs             = aws_kms_key.efs.arn
    s3              = aws_kms_key.s3.arn
    cloudwatch_logs = aws_kms_key.cloudwatch_logs.arn
    secrets_manager = aws_kms_key.secrets_manager.arn
    fsx             = aws_kms_key.fsx.arn
  }
}

output "cloudtrail_trail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.main.arn
}

output "cloudtrail_logs_bucket_name" {
  description = "Name of the CloudTrail logs S3 bucket"
  value       = aws_s3_bucket.cloudtrail_logs.id
}

output "config_recorder_name" {
  description = "Name of the Config recorder"
  value       = var.create_config_recorder ? aws_config_configuration_recorder.main[0].name : null
}

output "config_delivery_bucket_name" {
  description = "Name of the Config delivery S3 bucket"
  value       = var.create_config_recorder ? aws_s3_bucket.config_delivery[0].id : null
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = var.create_guardduty ? aws_guardduty_detector.main[0].id : null
}

output "security_hub_enabled" {
  description = "Whether Security Hub is enabled"
  value       = var.create_security_hub ? aws_securityhub_account.main[0].id : null
}
