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

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = var.project
      Env     = var.env
      Session = var.session
    }
  }
}

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
          Service = "ec2-image-builder.amazonaws.com"
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
    "arn:aws:iam::aws:policy/ImageBuilderFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess",
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
}

# Slurm Build Component
resource "aws_imagebuilder_component" "slurm_build" {
  name    = "${var.project}-${var.env}-${var.session}-slurm-build"
  version = var.component_version

  platform    = "Linux"
  description = "Build and install Slurm from source"

  data = file("${path.module}/components/slurm_build.yaml")

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-slurm-build"
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
}

# =============================================================================
# Image Builder Recipe
# =============================================================================

resource "aws_imagebuilder_image_recipe" "hpc_compute" {
  name         = "${var.project}-${var.env}-${var.session}-hpc-compute-recipe"
  version      = var.recipe_version
  description  = "HPC compute node image recipe with hardening and monitoring"
  parent_image = "arn:aws:imagebuilder:${data.aws_region.current.name}:aws:image/amazon-linux-2023-x86-64-pinned-access/e9c3d2b7a5c3d4e5"

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
# Image Builder Image Pipeline
# =============================================================================

resource "aws_imagebuilder_image_pipeline" "hpc_compute_weekly" {
  name        = "${var.project}-${var.env}-${var.session}-hpc-compute-weekly"
  description = "Weekly pipeline for building HPC compute images"

  image_recipe_arn                 = aws_imagebuilder_image_recipe.hpc_compute.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.hpc_compute.arn

  # Schedule: weekly on Sunday at 02:00 UTC
  schedule {
    schedule_expression                = "cron(0 2 ? * SUN *)"
    pipeline_execution_start_condition = "EXPRESSION_MATCH_ONLY"
  }

  status = "ENABLED"

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-hpc-compute-weekly-pipeline"
  }
}

# =============================================================================
# SSM Parameters for AMI tracking
# =============================================================================

resource "aws_ssm_parameter" "ami_current" {
  name  = "/hpc-testbed/ami/compute/current"
  type  = "String"
  value = var.initial_ami_id

  description = "Current HPC compute AMI ID"

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-ami-current"
  }
}

resource "aws_ssm_parameter" "ami_previous" {
  name  = "/hpc-testbed/ami/compute/previous"
  type  = "String"
  value = ""

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
