# Monitoring node: Prometheus, Grafana, node_exporter, cAdvisor, HPC scrape targets (Task 19)

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

  node_targets = compact([
    "localhost:9100",
    var.controller_private_ip != "" ? "${var.controller_private_ip}:9100" : "",
    var.login_private_ip != "" ? "${var.login_private_ip}:9100" : "",
  ])

  # Inline JSON list avoids heredoc indentation bugs that glued the first
  # target onto the same line as "- targets:" (invalid YAML).
  node_targets_json = jsonencode(local.node_targets)

  slurm_scrape_yaml = (
    var.slurm_exporter_enabled && var.controller_private_ip != ""
    ? <<-YAML
  - job_name: slurm
    static_configs:
      - targets: ['${var.controller_private_ip}:${var.slurm_exporter_port}']
        labels:
          role: slurm
YAML
    : ""
  )

  prometheus_yml = <<-PROM
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    metrics_path: /prometheus/metrics
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: monitoring

  - job_name: node
    static_configs:
      - targets: ${local.node_targets_json}
        labels:
          role: node

  - job_name: cadvisor
    static_configs:
      - targets: ['localhost:8081']
        labels:
          role: docker
${local.slurm_scrape_yaml}
PROM

  user_data = <<-USERDATA
#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/monitoring-user-data.log) 2>&1
echo "=== Monitoring user-data start $(date -u) ==="

yum update -y || true
# AL2023 ships curl-minimal; do not install full "curl" (package conflict).
yum install -y docker wget jq || dnf install -y docker wget jq
systemctl enable --now docker

mkdir -p /opt/prometheus /etc/prometheus /etc/prometheus/file_sd
cat > /etc/prometheus/prometheus.yml <<'PROM'
${local.prometheus_yml}
PROM

# ---------------------------------------------------------------------------
# Containers (host networking for simple scrape + ALB target ports)
# ---------------------------------------------------------------------------
docker rm -f prometheus 2>/dev/null || true
docker run -d --name prometheus --restart=always \
  --network host \
  -v /etc/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:v2.51.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --web.enable-lifecycle \
  --web.route-prefix=/prometheus \
  --web.external-url=/prometheus \
  --storage.tsdb.retention.time=15d || true

# Prefer host node_exporter from the compute AMI (already on :9100).
# Only start a container if nothing is listening on 9100.
docker rm -f node_exporter 2>/dev/null || true
if ss -lntp 2>/dev/null | grep -q ':9100'; then
  echo "Host node_exporter already on :9100 — skipping Docker node_exporter"
else
  docker run -d --name node_exporter --restart=always \
    --net=host \
    --pid=host \
    -v /:/host:ro,rslave \
    quay.io/prometheus/node-exporter:v1.7.0 \
    --path.rootfs=/host || true
fi

# cAdvisor on host port 8081 (avoid clash with login portal 8080)
docker rm -f cadvisor 2>/dev/null || true
docker run -d --name cadvisor --restart=always \
  --volume=/:/rootfs:ro \
  --volume=/var/run:/var/run:ro \
  --volume=/sys:/sys:ro \
  --volume=/var/lib/docker/:/var/lib/docker:ro \
  --volume=/dev/disk/:/dev/disk:ro \
  --publish=8081:8080 \
  --detach=true \
  --privileged \
  --device=/dev/kmsg \
  gcr.io/cadvisor/cadvisor:v0.49.1 || true

# ---------------------------------------------------------------------------
# Grafana provisioning
# ---------------------------------------------------------------------------
mkdir -p /opt/grafana/provisioning/dashboards \
         /opt/grafana/provisioning/datasources \
         /var/lib/grafana/dashboards

# Stable datasource uid "prometheus" so panels and community dashboards resolve
cat > /opt/grafana/provisioning/datasources/prometheus.yml <<'DS'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090/prometheus
    isDefault: true
    uid: prometheus
    editable: false
DS

cat > /opt/grafana/provisioning/dashboards/default.yml <<'DB'
apiVersion: 1
providers:
  - name: default
    orgId: 1
    folder: HPC
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
DB

# Built-in HPC overview — complete Grafana 10 schema, offline, always present
cat > /var/lib/grafana/dashboards/hpc-overview.json <<'DASH'
{
  "uid": "hpc-overview",
  "title": "HPC Overview",
  "tags": ["hpc", "slurm"],
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "refresh": "30s",
  "editable": true,
  "graphTooltip": 1,
  "time": { "from": "now-1h", "to": "now" },
  "timepicker": {},
  "templating": { "list": [] },
  "annotations": { "list": [] },
  "links": [],
  "panels": [
    {
      "id": 1,
      "type": "stat",
      "title": "Targets up",
      "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [{ "expr": "sum(up)", "refId": "A", "legendFormat": "up" }],
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "green", "value": 1 }
            ]
          }
        },
        "overrides": []
      },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"] }, "colorMode": "value", "graphMode": "none" }
    },
    {
      "id": 2,
      "type": "stat",
      "title": "Targets down",
      "gridPos": { "h": 4, "w": 6, "x": 6, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [{ "expr": "count(up == 0) or vector(0)", "refId": "A", "legendFormat": "down" }],
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "red", "value": 1 }
            ]
          }
        },
        "overrides": []
      },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"] }, "colorMode": "value", "graphMode": "none" }
    },
    {
      "id": 3,
      "type": "timeseries",
      "title": "CPU usage % (node)",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 4 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [{
        "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
        "legendFormat": "{{instance}}",
        "refId": "A"
      }],
      "fieldConfig": { "defaults": { "unit": "percent", "min": 0, "max": 100 }, "overrides": [] },
      "options": { "legend": { "displayMode": "list", "placement": "bottom" } }
    },
    {
      "id": 4,
      "type": "timeseries",
      "title": "Memory available %",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 4 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [{
        "expr": "(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100",
        "legendFormat": "{{instance}}",
        "refId": "A"
      }],
      "fieldConfig": { "defaults": { "unit": "percent", "min": 0, "max": 100 }, "overrides": [] },
      "options": { "legend": { "displayMode": "list", "placement": "bottom" } }
    },
    {
      "id": 5,
      "type": "timeseries",
      "title": "Disk used % (root)",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 12 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [{
        "expr": "100 - ((node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"}) * 100)",
        "legendFormat": "{{instance}}",
        "refId": "A"
      }],
      "fieldConfig": { "defaults": { "unit": "percent", "min": 0, "max": 100 }, "overrides": [] },
      "options": { "legend": { "displayMode": "list", "placement": "bottom" } }
    },
    {
      "id": 6,
      "type": "timeseries",
      "title": "Container CPU (cAdvisor)",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 12 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [{
        "expr": "sum by (name) (rate(container_cpu_usage_seconds_total{name!=\"\"}[5m]))",
        "legendFormat": "{{name}}",
        "refId": "A"
      }],
      "fieldConfig": { "defaults": {}, "overrides": [] },
      "options": { "legend": { "displayMode": "list", "placement": "bottom" } }
    },
    {
      "id": 7,
      "type": "table",
      "title": "Scrape targets",
      "gridPos": { "h": 8, "w": 24, "x": 0, "y": 20 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "targets": [{ "expr": "up", "format": "table", "instant": true, "refId": "A" }],
      "transformations": [
        { "id": "labelsToFields", "options": {} },
        { "id": "organize", "options": { "excludeByName": { "Time": true, "__name__": true } } }
      ],
      "options": { "showHeader": true }
    }
  ]
}
DASH

# Community dashboards (best-effort). grafana.com JSON uses __inputs; rewrite
# datasource refs to our stable uid so file provisioning actually loads them.
download_dashboard() {
  local id="$1" dest="$2" name="$3"
  echo "Fetching Grafana dashboard $${id} ($${name})..."
  if curl -fsSL --max-time 60 "https://grafana.com/api/dashboards/$${id}/revisions/latest/download" -o "/tmp/dash-$${id}.json"; then
    # Extract .dashboard if wrapped; force id=null, uid, and Prometheus datasource uid
    jq --arg uid "gnet-$${id}" '
      (if type == "object" and has("dashboard") then .dashboard else . end)
      | .id = null
      | .uid = $uid
      | walk(
          if type == "object" then
            if (.type? == "prometheus") or (.type? == "datasource") then
              .uid = "prometheus"
            elif has("datasource") and (.datasource | type == "string") then
              .datasource = {"type":"prometheus","uid":"prometheus"}
            elif has("datasource") and (.datasource | type == "object") then
              .datasource.uid = "prometheus" | .datasource.type = "prometheus"
            else . end
          else . end
        )
      | del(.__inputs, .__requires, .__elements)
    ' "/tmp/dash-$${id}.json" > "$dest" 2>/dev/null \
      || jq 'if has("dashboard") then .dashboard else . end | .id = null' "/tmp/dash-$${id}.json" > "$dest" \
      || cp "/tmp/dash-$${id}.json" "$dest"
    if jq -e '.title and .panels' "$dest" >/dev/null 2>&1; then
      echo "Installed $${name} -> $${dest}"
    else
      echo "WARN: $${name} JSON invalid after transform; removing"
      rm -f "$dest"
    fi
  else
    echo "WARN: could not download dashboard $${id} ($${name}); continuing with built-in only"
  fi
}

download_dashboard 1860 /var/lib/grafana/dashboards/node-exporter-full.json "Node Exporter Full" || true
download_dashboard 193  /var/lib/grafana/dashboards/docker-monitoring.json "Docker monitoring" || true
download_dashboard 14282 /var/lib/grafana/dashboards/cadvisor-exporter.json "cAdvisor exporter" || true

# Grafana runs as uid 472; ensure it can read provisioned files
chown -R 472:472 /var/lib/grafana/dashboards /opt/grafana/provisioning 2>/dev/null || true
chmod -R a+rX /var/lib/grafana/dashboards /opt/grafana/provisioning

# Validate built-in dashboard JSON before start
jq -e '.uid and .panels' /var/lib/grafana/dashboards/hpc-overview.json >/dev/null

# Grafana: serve_from_sub_path so ALB path /grafana works
docker rm -f grafana 2>/dev/null || true
docker run -d --name grafana --restart=always \
  --network host \
  -e GF_SECURITY_ADMIN_USER=admin \
  -e GF_SECURITY_ADMIN_PASSWORD=hpc-admin-change-me \
  -e GF_USERS_ALLOW_SIGN_UP=false \
  -e GF_SERVER_HTTP_PORT=3000 \
  -e GF_SERVER_ROOT_URL="%(protocol)s://%(domain)s/grafana/" \
  -e GF_SERVER_SERVE_FROM_SUB_PATH=true \
  -e GF_PATHS_PROVISIONING=/etc/grafana/provisioning \
  -v /opt/grafana/provisioning:/etc/grafana/provisioning:ro \
  -v /var/lib/grafana/dashboards:/var/lib/grafana/dashboards:ro \
  grafana/grafana:10.4.0 || true

echo "Monitoring node initialized $(date -u)" >> /var/log/monitoring-init.log
echo "=== Monitoring user-data end $(date -u) ==="
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
  description = "Monitoring node instance SG (Grafana/Prometheus/cAdvisor)"
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
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "node_exporter from VPC"
  }
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "cAdvisor from VPC"
  }

  dynamic "ingress" {
    for_each = var.alb_security_group_id != "" ? [1] : []
    content {
      from_port       = 3000
      to_port         = 3000
      protocol        = "tcp"
      security_groups = [var.alb_security_group_id]
      description     = "Grafana from portal ALB"
    }
  }
  dynamic "ingress" {
    for_each = var.alb_security_group_id != "" ? [1] : []
    content {
      from_port       = 9090
      to_port         = 9090
      protocol        = "tcp"
      security_groups = [var.alb_security_group_id]
      description     = "Prometheus from portal ALB"
    }
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
  count                       = var.create_monitoring ? 1 : 0
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.private_subnet_ids[0]
  vpc_security_group_ids = compact(concat(
    [aws_security_group.monitoring[0].id],
    try([var.security_group_ids["monitoring"]], [])
  ))
  iam_instance_profile        = aws_iam_instance_profile.monitoring[0].name
  key_name                    = var.ssh_key_name != "" ? var.ssh_key_name : null
  user_data                   = local.user_data
  user_data_replace_on_change = true

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
output "monitoring_security_group_id" {
  value = var.create_monitoring ? aws_security_group.monitoring[0].id : null
}
output "grafana_url" {
  value = var.create_monitoring ? "http://${aws_instance.monitoring[0].private_ip}:3000" : null
}
output "prometheus_url" {
  value = var.create_monitoring ? "http://${aws_instance.monitoring[0].private_ip}:9090" : null
}
output "grafana_path_hint" {
  value = "/grafana/"
}
output "prometheus_path_hint" {
  value = "/prometheus/"
}
