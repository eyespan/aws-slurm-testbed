# Network module for HPC Platform Operations Test Bed
# Implements VPC, subnets, route tables, security groups, S3 gateway endpoint, flow logs, and Route 53 private hosted zone

# =============================================================================
# VPC
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-vpc"
  }
}

# =============================================================================
# Internet Gateway
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-igw"
  }
}

# =============================================================================
# Public Subnets (one per AZ)
# =============================================================================

locals {
  azs = var.availability_zones
}

resource "aws_subnet" "public" {
  for_each = toset(local.azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, index(local.azs, each.key))
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-public-${each.key}"
    Type = "public"
    AZ   = each.key
  }
}

# =============================================================================
# Private Subnets (one per AZ)
# =============================================================================

resource "aws_subnet" "private" {
  for_each = toset(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, index(local.azs, each.key) + 100)
  availability_zone = each.key

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-private-${each.key}"
    Type = "private"
    AZ   = each.key
  }
}

# =============================================================================
# NAT Gateway (in public subnet)
# =============================================================================

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-nat-eip"
  }

  count = var.single_nat_gateway ? 1 : 0
}

resource "aws_nat_gateway" "main" {
  allocation_id = var.single_nat_gateway ? aws_eip.nat[0].id : null
  subnet_id     = var.single_nat_gateway ? aws_subnet.public[local.azs[0]].id : null

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-nat"
  }

  count = var.enable_nat_gateway && var.single_nat_gateway ? 1 : 0

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# NAT Gateway EIP for multi-NAT (when single_nat_gateway is false)
# =============================================================================

resource "aws_eip" "nat_multi" {
  domain = "vpc"

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-nat-eip-${each.key}"
  }

  for_each = toset(var.single_nat_gateway ? [] : local.azs)
}

resource "aws_nat_gateway" "multi" {
  allocation_id = aws_eip.nat_multi[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-nat-${each.key}"
  }

  for_each = toset(var.single_nat_gateway ? [] : local.azs)

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# Route Tables
# =============================================================================

# Public route table (with internet gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-public-rt"
    Type = "public"
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  for_each = toset(local.azs)

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

# Private route table (with NAT gateway)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : null
  }

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? null : aws_nat_gateway.multi[local.azs[0]].id
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-private-rt"
    Type = "private"
  }
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private" {
  for_each = toset(local.azs)

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private.id
}

# =============================================================================
# Security Groups
# =============================================================================

# Login tier security group
resource "aws_security_group" "login" {
  name        = "${var.project}-${var.env}-${var.session}-login-sg"
  description = "Security group for login nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP for status portal"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS for status portal"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-login-sg"
    Tier = "login"
  }
}

# Controller tier security group
resource "aws_security_group" "controller" {
  name        = "${var.project}-${var.env}-${var.session}-controller-sg"
  description = "Security group for Slurm controller"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from login nodes"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.login.id]
  }

  ingress {
    description     = "Slurmctld (6817) from login nodes"
    from_port       = 6817
    to_port         = 6817
    protocol        = "tcp"
    security_groups = [aws_security_group.login.id]
  }

  ingress {
    description = "Slurmctld (6817) from compute nodes"
    from_port   = 6817
    to_port     = 6817
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Slurmd (6818) from controller"
    from_port   = 6818
    to_port     = 6818
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "MariaDB (3306) from controller itself"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "EFS NFS (2049) from within VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-controller-sg"
    Tier = "controller"
  }
}

# Compute tier security group
resource "aws_security_group" "compute" {
  name        = "${var.project}-${var.env}-${var.session}-compute-sg"
  description = "Security group for Slurm compute nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from login nodes"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.login.id]
  }

  ingress {
    description = "Slurmd (6818) from controller"
    from_port   = 6818
    to_port     = 6818
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "EFS NFS (2049) from within VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-compute-sg"
    Tier = "compute"
  }
}

# Monitoring tier security group
resource "aws_security_group" "monitoring" {
  name        = "${var.project}-${var.env}-${var.session}-monitoring-sg"
  description = "Security group for monitoring nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from login nodes"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.login.id]
  }

  ingress {
    description = "Prometheus (9090) from within VPC"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Grafana (3000) from within VPC"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Node Exporter (9100) from within VPC"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "EFS NFS (2049) from within VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-monitoring-sg"
    Tier = "monitoring"
  }
}

# EFS security group
resource "aws_security_group" "efs" {
  name        = "${var.project}-${var.env}-${var.session}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "NFS (2049) from within VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-efs-sg"
    Tier = "storage"
  }
}

# =============================================================================
# S3 Gateway Endpoint
# =============================================================================

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint_route_table_association" "s3" {
  for_each = {
    public  = aws_route_table.public.id
    private = aws_route_table.private.id
  }

  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  route_table_id  = each.value
}

# =============================================================================
# VPC Flow Logs
# =============================================================================

data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = var.flow_logs_log_group_name
  retention_in_days = 30

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-flow-logs"
  }
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.project}-${var.env}-${var.session}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-flow-logs-role"
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project}-${var.env}-${var.session}-flow-logs-policy"

  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  traffic_type    = var.flow_logs_traffic_type
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn    = aws_iam_role.flow_logs.arn
  vpc_id          = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-flow-log"
  }
}

# =============================================================================
# Route 53 Private Hosted Zone
# =============================================================================

resource "aws_route53_zone" "private" {
  name = "hpc.internal"

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = {
    Name = "${var.project}-${var.env}-${var.session}-hpc-internal"
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

output "nat_gateway_ids" {
  description = "IDs of NAT gateways"
  value       = var.single_nat_gateway ? [aws_nat_gateway.main[0].id] : [for ngw in aws_nat_gateway.multi : ngw.id]
}

output "security_group_ids" {
  description = "IDs of created security groups"
  value = {
    login      = aws_security_group.login.id
    controller = aws_security_group.controller.id
    compute    = aws_security_group.compute.id
    monitoring = aws_security_group.monitoring.id
    efs        = aws_security_group.efs.id
  }
}

output "s3_endpoint_id" {
  description = "ID of the S3 gateway endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "flow_logs_cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for flow logs"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs.name : null
}

output "flow_logs_cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for flow logs"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs.arn : null
}

output "private_hosted_zone_id" {
  description = "ID of the Route 53 private hosted zone"
  value       = aws_route53_zone.private.id
}

output "private_hosted_zone_name" {
  description = "Name of the Route 53 private hosted zone"
  value       = aws_route53_zone.private.name
}
