# Controller module for HPC Platform Operations Test Bed
# Implements Slurm controller with slurmctld, slurmdbd, MariaDB, and configuration templates

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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
# IAM Role for Controller
# =============================================================================

resource "aws_iam_role" "controller" {
  name = "${var.project}-${var.env}-${var.session}-controller-role"

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

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-controller-role"
  }
}

# IAM Policy for Secrets Manager - Read munge key
resource "aws_iam_policy" "secrets_manager_read" {
  name = "${var.project}-${var.env}-${var.session}-secrets-manager-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.munge_key.arn
      }
    ]
  })

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-secrets-manager-read"
  }
}

# IAM Policy for SSM - Read parameters (AMI version)
resource "aws_iam_policy" "ssm_parameters_read" {
  name = "${var.project}-${var.env}-${var.session}-ssm-parameters-read"

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

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-ssm-parameters-read"
  }
}

# IAM Policy for EFS - Full access (for mounting and state)
resource "aws_iam_policy" "efs_full" {
  name = "${var.project}-${var.env}-${var.session}-efs-full"

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

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-efs-full"
  }
}

# Attach policies to controller role
resource "aws_iam_role_policy_attachment" "secrets_manager_read" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.secrets_manager_read.arn
}

resource "aws_iam_role_policy_attachment" "ssm_parameters_read" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.ssm_parameters_read.arn
}

resource "aws_iam_role_policy_attachment" "efs_full" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.efs_full.arn
}

# Instance profile for controller
resource "aws_iam_instance_profile" "controller" {
  name = "${var.project}-${var.env}-${var.session}-controller-profile"
  role = aws_iam_role.controller.name

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-controller-profile"
  }
}

# =============================================================================
# Secrets Manager - Munge Key
# =============================================================================

resource "aws_secretsmanager_secret" "munge_key" {
  name                    = "${var.project}-${var.env}-${var.session}-munge-key"
  description             = "Munge key for Slurm authentication"
  kms_key_id              = var.kms_key_arns.secrets_manager
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-munge-key"
  }
}

resource "aws_secretsmanager_secret_version" "munge_key" {
  secret_id = aws_secretsmanager_secret.munge_key.id

  secret_string = jsonencode({
    munge_key = base64encode(random_password.munge_key.result)
  })

  depends_on = [random_password.munge_key]
}

resource "random_password" "munge_key" {
  length  = 64
  special = false
}

# =============================================================================
# EFS State Directory Setup
# =============================================================================

# Placeholder for EFS slurm state directory setup (via user_data)
resource "null_resource" "efs_slurm_state_setup" {
  triggers = {
    file_system_id = var.efs_file_system_id
    timestamp      = timestamp()
  }
}

# =============================================================================
# Controller Instance
# =============================================================================

locals {
  # Database connection info (use empty strings when MariaDB is disabled)
  mariadb_endpoint = var.enable_mariadb ? aws_db_instance.mariadb[0].endpoint : ""
  mariadb_port     = var.enable_mariadb ? aws_db_instance.mariadb[0].port : ""

  slurm_conf = <<SLURMCONF
# Slurm controller configuration file
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
PartitionName=debug Priority=50 Default=YES MaxTime=24:00:00 State=UP Nodes=debug-1 State=UNKNOWN
PartitionName=std Priority=40 Default=NO MaxTime=7-00:00:00 State=UP Nodes=std-[1-3] State=UNKNOWN
NodeName=debug-1 NodeAddr=debug-1.hpc.internal CPUs=2 State=UNKNOWN
NodeName=std-1 NodeAddr=std-1.hpc.internal CPUs=2 State=UNKNOWN
NodeName=std-2 NodeAddr=std-2.hpc.internal CPUs=2 State=UNKNOWN
NodeName=std-3 NodeAddr=std-3.hpc.internal CPUs=2 State=UNKNOWN
SuspendTime=300
SchedulerType=sched/backfill
SLURMCONF

  slurmdbd_conf = <<SLURMDBDCONF
# Slurm DB Daemon configuration file
DBDHost=${var.project}-controller.${var.private_hosted_zone_name}
DbdPort=6819
DbdAuth=auth/mysql
DbdParams=${local.mariadb_endpoint}:${local.mariadb_port},${var.mariadb_db_name},${var.mariadb_username},${var.mariadb_password}
AccountingStorageType=accounting_storage/mysql
DbdRetainSeconds=300
SLURMDBDCONF

  cgroup_conf = <<CGROUPCONF
# Slurm cgroup configuration file
CgroupAutomount=yes
CgroupMountpoint=/sys/fs/cgroup
CgroupPlugin=controller/cgroup
TaskPlugin=task/affinity
CGROUPCONF

  user_data = <<USERDATA
#!/bin/bash
set -e

# Update system
yum update -y

# Install dependencies
yum install -y wget curl nfs-utils python3-pip jq

# Install Slurm dependencies
yum install -y gcc gcc-c++ make automake autoconf libtool perl perl-ExtUtils-MakeMaker openssl-devel pam-devel numactl-devel hwloc-devel lua-devel rrdtool-devel ncurses-devel man2html libibmad libibumad hpcg hwloc

# Install MariaDB (if enabled)
%{if var.enable_mariadb~}
yum install -y mariadb-server
%{endif~}

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
MUNGE_KEY=$(aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.munge_key.arn} --query SecretString --output text --region ${data.aws_region.current.name} | jq -r '.munge_key' | base64 -d)
echo "$MUNGE_KEY" > /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key

# Create munge user/service
useradd -m munge 2>/dev/null || true
systemctl enable --now munge 2>/dev/null || true

# Create Slurm configuration
echo '${local.slurm_conf}' > /opt/hpc/slurm.conf
echo '${local.slurmdbd_conf}' > /opt/hpc/slurmdbd.conf
echo '${local.cgroup_conf}' > /opt/hpc/cgroup.conf

cp /opt/hpc/slurm.conf /etc/slurm/slurm.conf
cp /opt/hpc/slurmdbd.conf /etc/slurm/slurmdbd.conf
cp /opt/hpc/cgroup.conf /etc/slurm/cgroup.conf
chown -R slurm:slurm /etc/slurm
chmod 600 /etc/slurm/*.conf

# Initialize MariaDB (if enabled)
%{if var.enable_mariadb~}
if [ ! -f /var/lib/mysql/ibdata1 ]; then
    mysql_install_db --user=mysql --datadir=/var/lib/mysql
    systemctl start mariadb
    sleep 10
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${var.mariadb_db_name}; CREATE USER '${var.mariadb_username}'@'localhost' IDENTIFIED BY '${var.mariadb_password}'; CREATE USER '${var.mariadb_username}'@'%' IDENTIFIED BY '${var.mariadb_password}'; GRANT ALL PRIVILEGES ON ${var.mariadb_db_name}.* TO '${var.mariadb_username}'@'localhost'; GRANT ALL PRIVILEGES ON ${var.mariadb_db_name}.* TO '${var.mariadb_username}'@'%'; FLUSH PRIVILEGES;"
    systemctl stop mariadb
fi
systemctl enable mariadb
systemctl start mariadb
%{endif~}

# Enable Slurm services
systemctl enable slurmctld slurmd slurmdbd
systemctl start slurmctld slurmd slurmdbd

echo "Controller node setup complete"
USERDATA
}

resource "aws_instance" "controller" {
  ami                    = var.ami_id
  instance_type          = var.controller_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.security_group_ids["controller"]]
  iam_instance_profile   = aws_iam_instance_profile.controller.name

  # Root block device with encryption
  root_block_device {
    volume_size           = var.controller_ebs_volume_size
    volume_type           = var.controller_ebs_volume_type
    iops                  = var.controller_ebs_volume_iops
    throughput            = var.controller_ebs_volume_throughput
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = var.kms_key_arns.ebs
  }

  # Additional EBS volume for Slurm state
  ebs_block_device {
    device_name = "/dev/sdh"
    volume_size = 100
    volume_type = "gp3"
    iops        = 3000
    throughput  = 125
    encrypted   = true
    kms_key_id  = var.kms_key_arns.ebs
  }

  # User data for bootstrapping
  user_data = local.user_data

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-controller"
    Role = "controller"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
}

# =============================================================================
# Debug Node (Static, always-on for canaries)
# =============================================================================

resource "aws_instance" "debug" {
  ami                    = var.ami_id
  instance_type          = var.debug_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.security_group_ids["compute"]]
  iam_instance_profile   = aws_iam_instance_profile.controller.name

  # Root block device with encryption
  root_block_device {
    volume_size           = var.controller_ebs_volume_size
    volume_type           = var.controller_ebs_volume_type
    iops                  = var.controller_ebs_volume_iops
    throughput            = var.controller_ebs_volume_throughput
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = var.kms_key_arns.ebs
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-debug"
    Role = "debug"
    Type = "static"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
}

# =============================================================================
# MariaDB RDS Instance (for slurmdbd)
# =============================================================================

resource "aws_db_subnet_group" "mariadb" {
  count = var.enable_mariadb ? 1 : 0

  name       = "${var.project}-${var.env}-${var.session}-mariadb-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-mariadb-subnet-group"
  }
}

resource "aws_db_instance" "mariadb" {
  count = var.enable_mariadb ? 1 : 0

  identifier           = "${var.project}-${var.env}-${var.session}-mariadb"
  engine               = "mariadb"
  engine_version       = "10.11.8"
  instance_class       = var.mariadb_instance_class
  allocated_storage    = var.mariadb_allocated_storage
  storage_type         = "gp2"
  db_name              = var.mariadb_db_name
  username             = var.mariadb_username
  password             = var.mariadb_password
  parameter_group_name = "default.mariadb-10.11"

  vpc_security_group_ids = [var.security_group_ids["controller"]]
  db_subnet_group_name   = aws_db_subnet_group.mariadb[0].name
  multi_az               = false
  publicly_accessible    = false

  backup_retention_period = 7
  storage_encrypted       = true
  kms_key_id              = var.kms_key_arns.secrets_manager

  skip_final_snapshot = true

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-mariadb"
  }
}

# =============================================================================
# EFS CloudWatch Alarms
# =============================================================================

# EFS burst credit balance alarm
resource "aws_cloudwatch_metric_alarm" "efs_burst_credits" {
  count = var.efs_file_system_id != "" ? 1 : 0

  alarm_name          = "${var.project}-${var.env}-${var.session}-controller-efs-burst-credits"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000000
  alarm_description   = "EFS burst credit balance is low for controller"
  dimensions = {
    FileSystemId = var.efs_file_system_id
  }
  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.name}:ec2:notify"
  ]

  tags = {
    Name     = "${var.project}-${var.env}-${var.session}-controller-efs-burst-credits"
    severity = "warning"
    sli      = "storage_health"
    runbook  = "https://github.com/yohannesm/cguru/hpc-testbed/runbooks/storage-issues.md"
  }
}

# EFS storage utilization alarm
resource "aws_cloudwatch_metric_alarm" "efs_storage_utilization" {
  count = var.efs_file_system_id != "" ? 1 : 0

  alarm_name          = "${var.project}-${var.env}-${var.session}-controller-efs-storage-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TotalFileSystemBytes"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 858993459200
  alarm_description   = "EFS storage utilization is above 85% for controller"
  dimensions = {
    FileSystemId = var.efs_file_system_id
  }
  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.name}:ec2:notify"
  ]

  tags = {
    Name     = "${var.project}-${var.env}-${var.session}-controller-efs-storage-utilization"
    severity = "warning"
    sli      = "storage_health"
    runbook  = "https://github.com/yohannesm/cguru/hpc-testbed/runbooks/storage-issues.md"
  }
}
