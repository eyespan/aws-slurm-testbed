# EC2 instances, security groups, and IAM roles for login node module

locals {
  # Common tags for all resources
  common_tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
  }

  # Login node user data script
  login_user_data = <<USERDATA
#!/bin/bash
set -e

# Update system
yum update -y

# Install dependencies
yum install -y wget curl nfs-utils python3-pip jq

# Install Slurm client tools
yum install -y slurm-slurmctld slurm-slurmd slurm-client

# Create slurm user
useradd -m -s /bin/bash slurm 2>/dev/null || true

# Create directories
mkdir -p /var/spool/slurmctld /var/spool/slurmd /etc/slurm /opt/hpc /shared/slurm-state
chown -R slurm:slurm /var/spool/slurmctld /var/spool/slurmd

# Mount EFS for Slurm state
echo "${var.efs_file_system_id}:/ /shared/slurm-state efs defaults,fsport=2049,x-systemd.automount 0 0" >> /etc/fstab
mount -a

# Create Munge key directory
mkdir -p /etc/munge /var/log/munge

# Fetch Munge key from Secrets Manager
MUNGE_KEY=$(aws secretsmanager get-secret-value --secret-id ${var.munge_key_secret_arn} --query SecretString --output text --region ${data.aws_region.current.name} | jq -r '.munge_key' | base64 -d)
echo "$MUNGE_KEY" > /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key

# Create munge user/service
useradd -m munge 2>/dev/null || true
systemctl enable --now munge 2>/dev/null || true

# Install and configure Slurm client
cat > /opt/hpc/slurm.conf <<'SLURMCONF'
# Slurm client configuration
ClusterName=hpc-cluster
SlurmctldHost=${var.project}-controller.${var.private_hosted_zone_name}
SlurmUser=slurm
SlurmctldPidFile=/var/spool/slurmctld/slurmctld.pid
SlurmctldLogDir=/var/log/slurmctld
SlurmctldPort=6817
SlurmdPidFile=/var/spool/slurmd/slurmd.pid
SlurmdLogDir=/var/log/slurmd
SlurmdPort=6818
SlurmSpoolDir=/var/spool/slurm
SlurmStateDir=/shared/slurm-state
AuthType=auth/munge
CredType=cred/munge
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=${var.project}-controller.${var.private_hosted_zone_name}
AccountingStoragePort=6819
PartitionName=debug Priority=50 Default=YES MaxTime=24:00:00 State=UP Nodes=debug-1
PartitionName=std Priority=40 Default=NO MaxTime=7-00:00:00 State=UP Nodes=std-[1-3]
NodeName=debug-1 NodeAddr=debug-1.hpc.internal CPUs=2
NodeName=std-1 NodeAddr=std-1.hpc.internal CPUs=2
NodeName=std-2 NodeAddr=std-2.hpc.internal CPUs=2
NodeName=std-3 NodeAddr=std-3.hpc.internal CPUs=2
SuspendTime=300
SchedulerType=sched/backfill
SLURMCONF

# Configure nsswitch.conf to use files for user lookup
sed -i 's/^passwd:.*/passwd:     files/' /etc/nsswitch.conf
sed -i 's/^shadow:.*/shadow:     files/' /etc/nsswitch.conf
sed -i 's/^group:.*/group:      files/' /etc/nsswitch.conf

# Copy configuration to Slurm config directory
cp /opt/hpc/slurm.conf /etc/slurm/slurm.conf
chown -R slurm:slurm /etc/slurm
chmod 600 /etc/slurm/slurm.conf

# Enable and start Slurm client services
systemctl enable slurmctld slurmd 2>/dev/null || true
systemctl start slurmctld slurmd 2>/dev/null || true

# Create shared directory on EFS
mkdir -p /shared
chown -R slurm:slurm /shared

# Record instance metadata
echo "Login node initialized at $(date)" >> /var/log/login-init.log
USERDATA

  # Debug node user data script
  debug_user_data = <<USERDATA
#!/bin/bash
set -e

# Update system
yum update -y

# Install dependencies
yum install -y wget curl nfs-utils python3-pip jq

# Install Slurm compute node components
yum install -y slurm-slurmd

# Create slurm user
useradd -m -s /bin/bash slurm 2>/dev/null || true

# Create directories
mkdir -p /var/spool/slurmd /etc/slurm /opt/hpc /shared/slurm-state
chown -R slurm:slurm /var/spool/slurmd

# Mount EFS for Slurm state
echo "${var.efs_file_system_id}:/ /shared/slurm-state efs defaults,fsport=2049,x-systemd.automount 0 0" >> /etc/fstab
mount -a

# Create Munge key directory
mkdir -p /etc/munge /var/log/munge

# Fetch Munge key from Secrets Manager
MUNGE_KEY=$(aws secretsmanager get-secret-value --secret-id ${var.munge_key_secret_arn} --query SecretString --output text --region ${data.aws_region.current.name} | jq -r '.munge_key' | base64 -d)
echo "$MUNGE_KEY" > /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key

# Create munge user/service
useradd -m munge 2>/dev/null || true
systemctl enable --now munge 2>/dev/null || true

# Install and configure Slurm compute node
cat > /opt/hpc/slurm.conf <<'SLURMCONF'
# Slurm compute node configuration
ClusterName=hpc-cluster
SlurmctldHost=${var.project}-controller.${var.private_hosted_zone_name}
SlurmUser=slurm
SlurmctldPidFile=/var/spool/slurmctld/slurmctld.pid
SlurmctldLogDir=/var/log/slurmctld
SlurmctldPort=6817
SlurmdPidFile=/var/spool/slurmd/slurmd.pid
SlurmdLogDir=/var/log/slurmd
SlurmdPort=6818
SlurmSpoolDir=/var/spool/slurm
SlurmStateDir=/shared/slurm-state
AuthType=auth/munge
CredType=cred/munge
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=${var.project}-controller.${var.private_hosted_zone_name}
AccountingStoragePort=6819
PartitionName=debug Priority=50 Default=YES MaxTime=24:00:00 State=UP Nodes=debug-1
PartitionName=std Priority=40 Default=NO MaxTime=7-00:00:00 State=UP Nodes=std-[1-3]
NodeName=debug-1 NodeAddr=debug-1.hpc.internal CPUs=2
NodeName=std-1 NodeAddr=std-1.hpc.internal CPUs=2
NodeName=std-2 NodeAddr=std-2.hpc.internal CPUs=2
NodeName=std-3 NodeAddr=std-3.hpc.internal CPUs=2
SuspendTime=300
SchedulerType=sched/backfill
SLURMCONF

# Copy configuration to Slurm config directory
cp /opt/hpc/slurm.conf /etc/slurm/slurm.conf
chown -R slurm:slurm /etc/slurm
chmod 600 /etc/slurm/slurm.conf

# Configure debug partition for static node
cat > /opt/hpc/partition_debug.conf <<'PARTITION'
# Debug partition configuration for static node
PartitionName=debug Priority=50 Default=YES MaxTime=24:00:00 State=UP Nodes=${var.project}-debug NodeAddr=${var.project}-debug.${var.private_hosted_zone_name} CPUs=2 State=UNKNOWN
PARTITION

# Create shared directory on EFS
mkdir -p /shared
chown -R slurm:slurm /shared

# Enable and start Slurmd
systemctl enable slurmd
systemctl start slurmd

# Record instance metadata
echo "Debug node initialized at $(date)" >> /var/log/debug-init.log
USERDATA
}

# =============================================================================
# IAM Role for Login Node - Least Privilege
# =============================================================================

resource "aws_iam_role" "login_node" {
  count = var.create_login_node ? 1 : 0

  name = "${var.project}-${var.env}-${var.session}-login-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-login-node-role"
  })
}

# IAM Policy for Secrets Manager - Read munge key
resource "aws_iam_policy" "secrets_manager_read_login" {
  count = var.create_login_node ? 1 : 0

  name = "${var.project}-${var.env}-${var.session}-secrets-manager-read-login"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = var.munge_key_secret_arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-secrets-manager-read-login"
  })
}

# IAM Policy for SSM - Read parameters (AMI version)
resource "aws_iam_policy" "ssm_parameters_read_login" {
  count = var.create_login_node ? 1 : 0

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/hpc-testbed/*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-ssm-parameters-read-login"
  })
}

# IAM Policy for EFS - Full access (for mounting)
resource "aws_iam_policy" "efs_full_login" {
  count = var.create_login_node ? 1 : 0

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-efs-full-login"
  })
}

# Attach policies to login node role
resource "aws_iam_role_policy_attachment" "secrets_manager_read_login" {
  count      = var.create_login_node ? 1 : 0
  role       = aws_iam_role.login_node[0].name
  policy_arn = aws_iam_policy.secrets_manager_read_login[0].arn
}

resource "aws_iam_role_policy_attachment" "ssm_parameters_read_login" {
  count      = var.create_login_node ? 1 : 0
  role       = aws_iam_role.login_node[0].name
  policy_arn = aws_iam_policy.ssm_parameters_read_login[0].arn
}

resource "aws_iam_role_policy_attachment" "efs_full_login" {
  count      = var.create_login_node ? 1 : 0
  role       = aws_iam_role.login_node[0].name
  policy_arn = aws_iam_policy.efs_full_login[0].arn
}

# Instance profile for login node
resource "aws_iam_instance_profile" "login_node" {
  count = var.create_login_node ? 1 : 0

  name = "${var.project}-${var.env}-${var.session}-login-node-profile"
  role = aws_iam_role.login_node[0].name

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-login-node-profile"
  })
}

# =============================================================================
# IAM Role for Debug Node - Least Privilege
# =============================================================================

resource "aws_iam_role" "debug_node" {
  count = var.create_debug_node ? 1 : 0

  name = "${var.project}-${var.env}-${var.session}-debug-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-debug-node-role"
  })
}

# IAM Policy for Secrets Manager - Read munge key
resource "aws_iam_policy" "secrets_manager_read_debug" {
  count = var.create_debug_node ? 1 : 0

  name = "${var.project}-${var.env}-${var.session}-secrets-manager-read-debug"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = var.munge_key_secret_arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-secrets-manager-read-debug"
  })
}

# IAM Policy for SSM - Read parameters (AMI version)
resource "aws_iam_policy" "ssm_parameters_read_debug" {
  count = var.create_debug_node ? 1 : 0

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/hpc-testbed/*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-ssm-parameters-read-debug"
  })
}

# IAM Policy for EFS - Full access (for mounting)
resource "aws_iam_policy" "efs_full_debug" {
  count = var.create_debug_node ? 1 : 0

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-efs-full-debug"
  })
}

# Attach policies to debug node role
resource "aws_iam_role_policy_attachment" "secrets_manager_read_debug" {
  count      = var.create_debug_node ? 1 : 0
  role       = aws_iam_role.debug_node[0].name
  policy_arn = aws_iam_policy.secrets_manager_read_debug[0].arn
}

resource "aws_iam_role_policy_attachment" "ssm_parameters_read_debug" {
  count      = var.create_debug_node ? 1 : 0
  role       = aws_iam_role.debug_node[0].name
  policy_arn = aws_iam_policy.ssm_parameters_read_debug[0].arn
}

resource "aws_iam_role_policy_attachment" "efs_full_debug" {
  count      = var.create_debug_node ? 1 : 0
  role       = aws_iam_role.debug_node[0].name
  policy_arn = aws_iam_policy.efs_full_debug[0].arn
}

# Instance profile for debug node
resource "aws_iam_instance_profile" "debug_node" {
  count = var.create_debug_node ? 1 : 0

  name = "${var.project}-${var.env}-${var.session}-debug-node-profile"
  role = aws_iam_role.debug_node[0].name

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-debug-node-profile"
  })
}

# =============================================================================
# Security Groups
# =============================================================================

# Security group for login node
resource "aws_security_group" "login_node" {
  count = var.create_login_node ? 1 : 0

  name        = "${var.project}-${var.env}-${var.session}-login-node-sg"
  description = "Security group for login node with SSH access"
  vpc_id      = var.vpc_id

  # SSH access from allowed CIDR blocks
  ingress {
    description = "SSH from allowed CIDR blocks"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-login-node-sg"
  })
}

# Security group for debug node (private, only accessible from login node)
resource "aws_security_group" "debug_node" {
  count = var.create_debug_node ? 1 : 0

  name        = "${var.project}-${var.env}-${var.session}-debug-node-sg"
  description = "Security group for debug node - private access only"
  vpc_id      = var.vpc_id

  # SSH access from login node only
  ingress {
    description = "SSH from login node"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [aws_security_group.login_node[0].id]
  }

  # Slurm port access from controller
  ingress {
    description = "Slurm from controller"
    from_port   = 6818
    to_port     = 6818
    protocol    = "tcp"
    security_groups = [aws_security_group.login_node[0].id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-debug-node-sg"
  })
}

# =============================================================================
# Login Node EC2 Instance
# =============================================================================

resource "aws_instance" "login_node" {
  count = var.create_login_node ? 1 : 0

  ami                    = var.ami_id
  instance_type          = var.login_instance_type
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.login_node[0].id]
  iam_instance_profile   = aws_iam_instance_profile.login_node[0].name

  # Root block device with encryption
  root_block_device {
    volume_size           = var.ebs_volume_size
    volume_type           = var.ebs_volume_type
    iops                  = var.ebs_volume_iops
    throughput            = var.ebs_volume_throughput
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = var.kms_key_arns["ebs"]
  }

  # User data for bootstrapping
  user_data = local.login_user_data

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-login"
    Role = "login"
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
}

# =============================================================================
# Debug Node EC2 Instance
# =============================================================================

resource "aws_instance" "debug_node" {
  count = var.create_debug_node ? 1 : 0

  ami                    = var.ami_id
  instance_type          = var.debug_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.debug_node[0].id]
  iam_instance_profile   = aws_iam_instance_profile.debug_node[0].name

  # Root block device with encryption
  root_block_device {
    volume_size           = var.ebs_volume_size
    volume_type           = var.ebs_volume_type
    iops                  = var.ebs_volume_iops
    throughput            = var.ebs_volume_throughput
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = var.kms_key_arns["ebs"]
  }

  # User data for bootstrapping
  user_data = local.debug_user_data

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-debug"
    Role = "debug"
    Type = "static"
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
}
