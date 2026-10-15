# EC2 Image Builder module for HPC Platform Operations Test Bed
# Implements AMI pipeline with AL2023 hardening, Slurm, munge, node_exporter, CloudWatch agent

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
data "aws_region" "current" {}


# =============================================================================
# IAM Roles and Policies
# =============================================================================

# Image Builder role for creating and managing AMIs
resource "aws_iam_role" "image_builder" {
  name = "${var.project}-${var.env}-${var.session}-image-builder-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "ec2.amazonaws.com",
            "imagebuilder.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-image-builder-role"
  }
}

# Attach managed policies for Image Builder
resource "aws_iam_role_policy_attachment" "image_builder_managed" {
  for_each = toset([
    "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.image_builder.name
  policy_arn = each.value
}

# Custom policy for SSM parameter access (for AMI promotion)
resource "aws_iam_policy" "image_builder_ssm" {
  name = "${var.project}-${var.env}-${var.session}-image-builder-ssm-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/hpc-testbed/ami/compute/current",
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/hpc-testbed/ami/compute/previous"
        ]
      }
    ]
  })

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-image-builder-ssm-policy"
  }
}

resource "aws_iam_role_policy_attachment" "image_builder_ssm" {
  role       = aws_iam_role.image_builder.name
  policy_arn = aws_iam_policy.image_builder_ssm.arn
}

# Custom policy for CloudWatch Logs
resource "aws_iam_policy" "image_builder_logs" {
  name = "${var.project}-${var.env}-${var.session}-image-builder-logs-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/imagebuilder/*"
      }
    ]
  })

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-image-builder-logs-policy"
  }
}

resource "aws_iam_role_policy_attachment" "image_builder_logs" {
  role       = aws_iam_role.image_builder.name
  policy_arn = aws_iam_policy.image_builder_logs.arn
}

# S3 log uploads to the CloudTrail/logs bucket (KMS-encrypted) require explicit
# s3:PutObject + kms:GenerateDataKey. Without this, pipeline fails with:
#   AccessDenied: ... is not authorized to perform: kms:GenerateDataKey
resource "aws_iam_policy" "image_builder_s3_logs" {
  name = "${var.project}-${var.env}-${var.session}-image-builder-s3-logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "S3LogBucket"
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:GetObject",
            "s3:AbortMultipartUpload",
            "s3:ListBucket",
            "s3:GetBucketLocation",
            "s3:ListBucketMultipartUploads",
            "s3:ListMultipartUploadParts"
          ]
          Resource = [
            "arn:aws:s3:::${var.log_bucket_name}",
            "arn:aws:s3:::${var.log_bucket_name}/*"
          ]
        }
      ],
      length(var.log_bucket_kms_key_arn) > 0 ? [
        {
          Sid    = "KmsForEncryptedLogBucket"
          Effect = "Allow"
          Action = [
            "kms:Encrypt",
            "kms:Decrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey*",
            "kms:DescribeKey"
          ]
          Resource = [var.log_bucket_kms_key_arn]
        }
      ] : []
    )
  })

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-image-builder-s3-logs"
  }
}

resource "aws_iam_role_policy_attachment" "image_builder_s3_logs" {
  role       = aws_iam_role.image_builder.name
  policy_arn = aws_iam_policy.image_builder_s3_logs.arn
}

# =============================================================================
# Image Builder Components (from inline YAML)
# =============================================================================

# AL2023 Hardening Component
resource "aws_imagebuilder_component" "al2023_hardening" {
  name    = "${var.project}-${var.env}-${var.session}-al2023-hardening"
  version = var.component_version

  platform    = "Linux"
  description = "AL2023 security hardening component"

  data = file("${path.module}/components/al2023_hardening.yaml")

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-al2023-hardening"
  }

  # Version bumps replace the resource; create new version before deleting old
  # so pipeline/recipe never reference a deleted component ARN.
  lifecycle {
    create_before_destroy = true
  }
}

# Slurm Build Component
resource "aws_imagebuilder_component" "slurm_build" {
  name    = "${var.project}-${var.env}-${var.session}-slurm-build"
  version = var.component_version

  platform    = "Linux"
  description = "Build and install Slurm from source (MySQL accounting required)"

  data = file("${path.module}/components/slurm_build.yaml")

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-slurm-build"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Munge Component
resource "aws_imagebuilder_component" "munge" {
  name    = "${var.project}-${var.env}-${var.session}-munge"
  version = var.component_version

  platform    = "Linux"
  description = "Install and configure munge for Slurm authentication"

  data = file("${path.module}/components/munge.yaml")

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-munge"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Node Exporter Component
resource "aws_imagebuilder_component" "node_exporter" {
  name    = "${var.project}-${var.env}-${var.session}-node-exporter"
  version = var.component_version

  platform    = "Linux"
  description = "Install and configure node_exporter for system metrics"

  data = file("${path.module}/components/node_exporter.yaml")

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-node-exporter"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch Agent Component
resource "aws_imagebuilder_component" "cloudwatch_agent" {
  name    = "${var.project}-${var.env}-${var.session}-cloudwatch-agent"
  version = var.component_version

  platform    = "Linux"
  description = "Install and configure CloudWatch agent"

  data = file("${path.module}/components/cloudwatch_agent.yaml")

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-cloudwatch-agent"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Image Builder Recipe
# =============================================================================

resource "aws_imagebuilder_image_recipe" "hpc_compute" {
  name         = "${var.project}-${var.env}-${var.session}-hpc-compute-recipe"
  version      = var.recipe_version
  description  = "HPC compute node image recipe with hardening and monitoring"
  # AMI ID is a supported parent_image format
  parent_image = data.aws_ssm_parameter.al2023.value

  component {
    component_arn = aws_imagebuilder_component.al2023_hardening.arn
  }

  component {
    component_arn = aws_imagebuilder_component.munge.arn
  }

  component {
    component_arn = aws_imagebuilder_component.slurm_build.arn
  }

  component {
    component_arn = aws_imagebuilder_component.node_exporter.arn
  }

  component {
    component_arn = aws_imagebuilder_component.cloudwatch_agent.arn
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-hpc-compute-recipe"
  }

  # Recipe versions are immutable; create new version before deleting old so the
  # pipeline can move off the old ARN first (avoids ResourceDependencyException).
  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Image Builder Infrastructure Configuration
# =============================================================================

resource "aws_imagebuilder_infrastructure_configuration" "hpc_compute" {
  name        = "${var.project}-${var.env}-${var.session}-hpc-compute-infrastructure"
  description = "Infrastructure configuration for HPC compute image builds"

  instance_profile_name = aws_iam_instance_profile.image_builder.name
  instance_types        = [var.build_instance_type]
  logging {
    s3_logs {
      s3_bucket_name = var.log_bucket_name
      s3_key_prefix  = "image-builder-logs"
    }
  }

  subnet_id                     = var.subnet_id
  security_group_ids            = [var.security_group_id]
  terminate_instance_on_failure = false

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-hpc-compute-infrastructure"
  }
}

# Instance profile for Image Builder
resource "aws_iam_instance_profile" "image_builder" {
  name = "${var.project}-${var.env}-${var.session}-image-builder-profile"
  role = aws_iam_role.image_builder.name

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-image-builder-profile"
  }
}


# =============================================================================
# Distribution configuration (required to produce a usable AMI in-account)
# =============================================================================

resource "aws_imagebuilder_distribution_configuration" "hpc_compute" {
  name        = "${var.project}-${var.env}-${var.session}-hpc-compute-dist"
  description = "Distribute HPC compute AMI to this account/region"

  distribution {
    region = data.aws_region.current.name

    ami_distribution_configuration {
      name = "${var.project}-hpc-{{ imagebuilder:buildDate }}"

      ami_tags = {
        Project = var.project
        Env     = var.env
        Session = var.session
        Name    = "${var.project}-${var.env}-${var.session}-hpc-ami"
        Role    = "hpc-compute"
      }
    }
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-hpc-compute-dist"
  }
}

# =============================================================================
# Image Builder Image Pipeline
# =============================================================================

resource "aws_imagebuilder_image_pipeline" "hpc_compute_weekly" {
  name        = "${var.project}-${var.env}-${var.session}-hpc-compute-weekly"
  description = "HPC compute image pipeline (weekly schedule + on-demand via make ami-build)"

  image_recipe_arn                   = aws_imagebuilder_image_recipe.hpc_compute.arn
  infrastructure_configuration_arn   = aws_imagebuilder_infrastructure_configuration.hpc_compute.arn
  distribution_configuration_arn     = aws_imagebuilder_distribution_configuration.hpc_compute.arn

  # Required in accounts that already have an SSM inventory / State Manager
  # association (Inspector, org policies, etc.). Default true makes Image Builder
  # create a second inventory association → InventoryCollection fails and the
  # whole build is marked FAILED even when components succeeded.
  enhanced_image_metadata_enabled = false

  # Weekly refresh only — does NOT run on terraform apply.
  # First/usable AMI: run `make ami-build` (starts execution, waits, promotes to SSM).
  schedule {
    schedule_expression                = "cron(0 2 ? * SUN *)"
    pipeline_execution_start_condition = "EXPRESSION_MATCH_ONLY"
  }

  image_tests_configuration {
    image_tests_enabled = false
  }

  status = "ENABLED"

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-hpc-compute-weekly-pipeline"
  }
}

# Optional: build an AMI during terraform apply (blocks 45–90 min). Prefer `make ami-build`.
resource "aws_imagebuilder_image" "hpc_compute_on_apply" {
  count = var.build_ami_on_apply ? 1 : 0

  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.hpc_compute.arn
  image_recipe_arn                 = aws_imagebuilder_image_recipe.hpc_compute.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.hpc_compute.arn

  enhanced_image_metadata_enabled = false

  image_tests_configuration {
    image_tests_enabled = false
  }

  timeouts {
    create = "120m"
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-hpc-compute-image"
  }
}

# =============================================================================
# SSM Parameters for AMI tracking
# =============================================================================

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_ssm_parameter" "ami_current" {
  name  = "/hpc-testbed/ami/compute/current"
  type  = "String"
  value = var.initial_ami_id != "" ? var.initial_ami_id : data.aws_ssm_parameter.al2023.value

  lifecycle {
    ignore_changes = [value]
  }

  description = "Current HPC compute AMI ID"

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-ami-current"
  }
}

resource "aws_ssm_parameter" "ami_previous" {
  name  = "/hpc-testbed/ami/compute/previous"
  type  = "String"
  value = var.initial_ami_id != "" ? var.initial_ami_id : data.aws_ssm_parameter.al2023.value

  lifecycle {
    ignore_changes = [value]
  }

  description = "Previous HPC compute AMI ID for rollback"

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-ami-previous"
  }
}

# =============================================================================
# KMS Key for AMI encryption
# =============================================================================

resource "aws_kms_key" "ami_encryption" {
  description             = "KMS key for HPC compute AMI encryption"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-ami-encryption-key"
  }
}

resource "aws_kms_alias" "ami_encryption" {
  name          = "alias/${var.project}-${var.env}-${var.session}-ami-encryption"
  target_key_id = aws_kms_key.ami_encryption.key_id
}

# =============================================================================
# Outputs
# =============================================================================

output "image_recipe_arn" {
  description = "ARN of the HPC compute image recipe"
  value       = aws_imagebuilder_image_recipe.hpc_compute.arn
}

output "image_pipeline_arn" {
  description = "ARN of the HPC compute image pipeline"
  value       = aws_imagebuilder_image_pipeline.hpc_compute_weekly.arn
}

output "infrastructure_configuration_arn" {
  description = "ARN of the infrastructure configuration"
  value       = aws_imagebuilder_infrastructure_configuration.hpc_compute.arn
}

output "ami_ssm_parameter_current" {
  description = "SSM parameter name for current AMI"
  value       = aws_ssm_parameter.ami_current.name
}

output "ami_ssm_parameter_previous" {
  description = "SSM parameter name for previous AMI"
  value       = aws_ssm_parameter.ami_previous.name
}

output "image_builder_role_arn" {
  description = "ARN of the Image Builder IAM role"
  value       = aws_iam_role.image_builder.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key for AMI encryption"
  value       = aws_kms_key.ami_encryption.arn
}

output "distribution_configuration_arn" {
  description = "ARN of the Image Builder distribution configuration"
  value       = aws_imagebuilder_distribution_configuration.hpc_compute.arn
}

output "on_apply_image_arn" {
  description = "ARN of the image built during apply (null if build_ami_on_apply is false)"
  value       = try(aws_imagebuilder_image.hpc_compute_on_apply[0].arn, null)
}
