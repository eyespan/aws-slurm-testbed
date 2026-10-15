# Monitoring node: Prometheus, Grafana, Slurm exporter targets (Task 19)

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
    Role    = "monitoring"
  }

  user_data = <<-USERDATA
#!/bin/bash
set -euo pipefail
yum update -y
yum install -y docker wget curl jq
systemctl enable --now docker

# Prometheus
mkdir -p /opt/prometheus /etc/prometheus
cat > /etc/prometheus/prometheus.yml <<'PROM'
global:
  scrape_interval: 30s
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']
  - job_name: node
    static_configs:
      - targets: ['localhost:9100']
  - job_name: slurm
    static_configs:
      - targets: ['${var.controller_private_ip}:8080']
PROM

docker run -d --name prometheus --restart=always \
  -p 9090:9090 \
  -v /etc/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus:v2.51.0 || true

# node_exporter
docker run -d --name node_exporter --restart=always \
  --net=host \
  --pid=host \
  -v /:/host:ro,rslave \
  quay.io/prometheus/node-exporter:v1.7.0 \
  --path.rootfs=/host || true

# Grafana with provisioned dashboards
mkdir -p /opt/grafana/provisioning/dashboards /opt/grafana/provisioning/datasources /var/lib/grafana/dashboards
cat > /opt/grafana/provisioning/datasources/prometheus.yml <<'DS'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
DS
cat > /opt/grafana/provisioning/dashboards/default.yml <<'DB'
apiVersion: 1
providers:
  - name: default
    orgId: 1
    folder: HPC
    type: file
    options:
      path: /var/lib/grafana/dashboards
DB
# Minimal dashboard JSON
cat > /var/lib/grafana/dashboards/hpc-overview.json <<'DASH'
{"dashboard":{"title":"HPC Overview","panels":[{"type":"stat","title":"Targets up","targets":[{"expr":"up"}]}],"schemaVersion":39},"overwrite":true}
DASH

docker run -d --name grafana --restart=always \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=hpc-admin-change-me \
  -e GF_USERS_ALLOW_SIGN_UP=false \
  -v /opt/grafana/provisioning:/etc/grafana/provisioning \
  -v /var/lib/grafana/dashboards:/var/lib/grafana/dashboards \
  grafana/grafana:10.4.0 || true

echo "Monitoring node initialized $(date)" >> /var/log/monitoring-init.log
USERDATA
}

resource "aws_iam_role" "monitoring" {
  count = var.create_monitoring ? 1 : 0
  name  = "${var.project}-${var.env}-${var.session}-monitoring-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = merge(local.common_tags, { Name = "${var.project}-monitoring-role" })
}

resource "aws_iam_role_policy_attachment" "monitoring_ssm" {
  count      = var.create_monitoring ? 1 : 0
  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "monitoring" {
  count = var.create_monitoring ? 1 : 0
  name  = "${var.project}-${var.env}-${var.session}-monitoring-profile"
  role  = aws_iam_role.monitoring[0].name
}

resource "aws_security_group" "monitoring" {
  count       = var.create_monitoring ? 1 : 0
  name        = "${var.project}-${var.env}-${var.session}-monitoring-instance-sg"
  description = "Monitoring node SG"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Grafana from VPC"
  }
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Prometheus from VPC"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project}-monitoring-sg" })
}

resource "aws_instance" "monitoring" {
  count                  = var.create_monitoring ? 1 : 0
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.monitoring[0].id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring[0].name
  key_name               = var.ssh_key_name != "" ? var.ssh_key_name : null
  user_data              = local.user_data

  root_block_device {
    volume_size           = var.ebs_volume_size
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = try(var.kms_key_arns["ebs"], null)
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-monitoring"
  })

  lifecycle { ignore_changes = [ami] }
}

resource "aws_route53_record" "monitoring" {
  count   = var.create_monitoring ? 1 : 0
  zone_id = var.private_hosted_zone_id
  name    = "monitoring.${var.private_hosted_zone_name}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.monitoring[0].private_ip]
}

output "monitoring_instance_id" {
  value = var.create_monitoring ? aws_instance.monitoring[0].id : null
}
output "monitoring_private_ip" {
  value = var.create_monitoring ? aws_instance.monitoring[0].private_ip : null
}
output "grafana_url" {
  value = var.create_monitoring ? "http://${aws_instance.monitoring[0].private_ip}:3000" : null
}
output "prometheus_url" {
  value = var.create_monitoring ? "http://${aws_instance.monitoring[0].private_ip}:9090" : null
}
