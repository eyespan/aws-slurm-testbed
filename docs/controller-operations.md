# Slurm Controller Operations Guide

## Overview

The Slurm controller node runs `slurmctld` and `slurmdbd` services to manage job scheduling and accounting. This guide covers deployment, operation, and recovery procedures.

## Architecture

The controller node consists of:

- **slurmctld**: Main Slurm controller daemon
- **slurmdbd**: Slurm database daemon for accounting
- **MariaDB**: Database for Slurm accounting data
- **EFS**: Shared filesystem for Slurm state persistence

## Deployment

### Prerequisites

- VPC with private subnets
- EFS file system created
- KMS keys configured
- IAM role with least-privilege permissions
- Munge key stored in Secrets Manager

### Terraform Deployment

```bash
cd terraform
terraform init
terraform validate
terraform apply -target=module.controller -auto-approve
```

### Manual Deployment

1. Launch the controller instance using the provided AMI
2. Configure EFS mount points
3. Install Slurm packages
4. Deploy configuration files from `config/slurm/`
5. Start services

```bash
# Mount EFS
mkdir -p /shared/slurm-state
mount -t efs <efs-file-system-id>:/ /shared/slurm-state

# Install Slurm
yum install -y slurm-slurmctld slurm-slurmd slurm-slurmdbd

# Deploy configuration
cp config/slurm/*.conf /etc/slurm/

# Start services
systemctl enable slurmctld slurmd slurmdbd
systemctl start slurmctld slurmd slurmdbd
```

## Configuration Files

### slurm.conf

Main Slurm configuration file. Key parameters:

- **ClusterName**: Name of the Slurm cluster
- **SlurmctldHost**: Controller node hostname and IP
- **PartitionName**: Partition definitions (debug, std)
- **NodeName**: Node definitions
- **AccountingStorageType**: Enable accounting with slurmdbd
- **PowerManagement**: Suspend/resume settings

### slurmdbd.conf

Database daemon configuration. Key parameters:

- **DBDHost**: Database host
- **DbdAuth**: Authentication method
- **DbdParams**: Database connection parameters
- **AccountingStorageType**: Storage type (mysql)

### cgroup.conf

Cgroup management configuration. Key parameters:

- **CgroupAutomount**: Enable cgroup mounting
- **CgroupMountpoint**: Cgroup mount point
- **TaskPlugin**: Task management plugin

## Operations

### Checking Service Status

```bash
# Check all Slurm services
systemctl status slurmctld slurmd slurmdbd

# Check specific service
systemctl status slurmctld
```

### Viewing Logs

```bash
# Slurmctld logs
tail -f /var/log/slurmctld/slurmctld.log

# Slurmd logs
tail -f /var/log/slurmd/slurmd.log

# Slurmdbd logs
tail -f /var/log/slurmdbd/slurmdbd.log
```

### Testing Connectivity

```bash
# Test Slurmctld
scontrol show node

# Test Slurmdbd
sacctmgr show cluster

# Test MariaDB connection
mysql -u slurm -p -e "SHOW DATABASES"
mysql -h hpc-testbed-dev-070bc5b7-mariadb.c78uuyai6glq.us-east-1.rds.amazonaws.com -P 3306 -u slurm -p -e "SHOW DATABASES;"
```

## Recovery Procedures

### Controller Node Recovery

When the controller node fails, queued jobs should not be lost due to state persistence on EFS.

#### Step 1: Launch Replacement Instance

1. Launch a new instance using the same AMI
2. Configure with the same EFS mount points
3. Assign the same IAM role

#### Step 2: Restore Configuration

```bash
# Mount EFS for state
mkdir -p /shared/slurm-state
mount -t efs <efs-file-system-id>:/ /shared/slurm-state

# Ensure configuration files exist
ls -la /etc/slurm/
```

#### Step 3: Start Services

```bash
# Start Slurm services
systemctl enable slurmctld slurmd slurmdbd
systemctl start slurmctld slurmd slurmdbd

# Verify state restoration
scontrol show node
sacctmgr show cluster
```

#### Step 4: Verify Job State

```bash
# Check queued jobs
squeue

# Check completed jobs
sacct

# Verify accounting data
sacctmgr show accounts
```

### EFS State Recovery

If EFS data is corrupted or lost:

1. Check EFS mount status

```bash
mount | grep efs
df -h /shared/slurm-state
```

2. If EFS is unreachable, check network configuration

```bash
# Verify VPC routing
ip route

# Verify security groups
aws ec2 describe-security-groups --group-ids <security-group-id>
```

3. Check EFS file system health in AWS Console

### Database Recovery

If MariaDB is unavailable:

1. Check MariaDB service status

```bash
systemctl status mariadb
```

2. If MariaDB is down, restart it

```bash
systemctl restart mariadb
```

3. Verify database connectivity

```bash
mysql -u slurm -p -e "SELECT 1"
mysql -h hpc-testbed-dev-070bc5b7-mariadb.c78uuyai6glq.us-east-1.rds.amazonaws.com -P 3306 -u slurm -p -e "SELECT 1"
```

4. Check Slurmdbd connection

```bash
systemctl restart slurmdbd
journalctl -u slurmdbd -f
```

### Munge Key Recovery

If the Munge key is lost:

1. Generate a new key

```bash
# Generate new key
python3 -c "import secrets; print(secrets.token_urlsafe(64))"
```

2. Update Munge key

```bash
# Save new key
echo "<new-key>" > /etc/munge/munge.key

# Set permissions
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
```

3. Restart services

```bash
systemctl restart munge
systemctl restart slurmctld slurmd slurmdbd
```

## Monitoring

### CloudWatch Alarms

Monitor the following metrics:

- **EFS Burst Credits**: Alert when below 1,000,000
- **EFS Storage Utilization**: Alert when above 85%
- **EFS Throughput**: Alert when low

### Health Checks

```bash
# Run health check script
python3 /opt/hpc/scripts/controller_setup.py check-health

# Check disk space
df -h

# Check memory usage
free -h

# Check CPU usage
top
```

## Troubleshooting

### Common Issues

#### Slurmctld Won't Start

**Symptoms**: Service fails to start, error in logs

**Solutions**:

1. Check configuration syntax

```bash
scontrol show config
```

2. Verify EFS mount

```bash
df -h /shared/slurm-state
```

3. Check permissions

```bash
ls -la /var/spool/slurmctld
chown -R slurm:slurm /var/spool/slurmctld
```

#### Slurmdbd Can't Connect to Database

**Symptoms**: Connection refused in logs

**Solutions**:

1. Verify MariaDB is running

```bash
systemctl status mariadb
```

2. Check database credentials

```bash
# Test connection
mysql -u slurm -p -h <db-host> -e "SELECT 1"
```

3. Verify network connectivity

```bash
telnet <db-host> 3306
```

#### Node Communication Issues

**Symptoms**: Nodes not communicating with controller

**Solutions**:

1. Check firewall rules

```bash
# Verify ports are open
netstat -tlnp | grep 6817
netstat -tlnp | grep 6818
```

2. Verify security groups

```bash
aws ec2 describe-security-groups --group-ids <security-group-id>
```

3. Check Munge key

```bash
# Verify Munge is running
systemctl status munge

# Test Munge
munge -n | unmunge
```

## Maintenance

### Upgrading Slurm

1. Backup configuration

```bash
cp -r /etc/slurm /etc/slurm.backup.$(date +%Y%m%d)
```

2. Install new version

```bash
yum update -y slurm-slurmctld slurm-slurmd slurm-slurmdbd
```

3. Verify configuration compatibility

```bash
scontrol show config
```

4. Restart services

```bash
systemctl restart slurmctld slurmd slurmdbd
```

5. Update version in configuration

```bash
# Update slurm.conf
sed -i "s/Version=.*/Version=23.02.4/" /etc/slurm/slurm.conf
```

### Backing Up State

```bash
# Backup Slurm state
tar -czvf /tmp/slurm-state-backup.tar.gz /var/spool/slurmctld/

# Backup configuration
tar -czvf /tmp/slurm-config-backup.tar.gz /etc/slurm/

# Backup EFS state (if not using EFS backups)
aws efs describe-file-systems --file-system-id <efs-id>
```

## Related Documentation

- [Slurm Documentation](https://slurm.schedmd.com/documentation.html)
- [Slurmdbd Documentation](https://slurm.schedmd.com/slurmdbd.html)
- [EFS Best Practices](https://docs.aws.amazon.com/efs/latest/ug/best-practices.html)
- [Slurm Quick Reference](https://slurm.schedmd.com/quickstart.html)
