# Login Node Operations Guide

## Overview

The login node provides SSH access to the HPC cluster and serves as the entry point for job submission and interactive testing. The debug node is a static compute node for interactive Slurm job testing.

## Architecture

The login node module provisions:

- **Login Node**: `t3.micro` EC2 instance in public subnet for SSH access
- **Debug Node**: `t3.micro` EC2 instance in private subnet for interactive testing

Both nodes:
- Have EBS volume encryption enabled
- Use least-privilege IAM roles
- Mount EFS at `/shared`
- Configure Munge for Slurm authentication

## Deployment

### Prerequisites

- VPC with public and private subnets
- EFS file system created
- KMS keys configured
- Controller module deployed (for Munge key and Slurm configuration)
- IAM role with Secrets Manager access

### Terraform Deployment

```bash
cd terraform
terraform init
terraform validate
terraform apply -target=module.login -auto-approve
```

### Manual Deployment

1. Launch the login node instance using the provided AMI
2. Configure EFS mount points
3. Install Slurm packages
4. Deploy configuration files
5. Start services

## SSH Access

### Login Node

The login node is accessible from allowed CIDR blocks via SSH:

```bash
# SSH to login node
ssh -i ~/.ssh/your-key.pem ec2-user@<login-node-public-ip>

# From login node, SSH to debug node
ssh ec2-user@<debug-node-private-ip>
```

### Debug Node

The debug node is in a private subnet and only accessible via the login node:

```bash
# SSH from login node to debug node
ssh ec2-user@<debug-node-private-ip>
```

## Configuration Files

### Slurm Configuration

The login node uses `slurm-client` packages with the following configuration:

- **slurm.conf**: Main Slurm configuration pointing to controller
- **Authentication**: Uses Munge for authentication
- **Partitions**: debug (interactive), std (batch)

### EFS Mount

Both nodes mount EFS at `/shared/slurm-state`:

```bash
# Check EFS mount
df -h /shared/slurm-state

# Check EFS access
ls -la /shared/
```

## Operations

### Checking Service Status

```bash
# On login node
systemctl status slurmctld slurmd munge

# On debug node
systemctl status slurmd munge
```

### Testing Connectivity

```bash
# From login node, test Slurm
sinfo
squeue
scontrol show node

# From login node, test SSH to debug node
ssh ec2-user@<debug-node-private-ip>

# From debug node, test Slurm
sinfo
```

### Viewing Logs

```bash
# Slurm logs
tail -f /var/log/slurmctld/slurmctld.log
tail -f /var/log/slurmd/slurmd.log

# Munge logs
tail -f /var/log/munge/munged.log

# Cloud-init logs
journalctl -u cloud-init -f
```

## Interactive Testing

### Using the Debug Node

The debug node is configured as part of the debug partition for interactive testing:

```bash
# From login node, submit interactive job to debug partition
srun --partition=debug --nodes=1 --ntasks=1 --time=01:00:00 --pty /bin/bash

# From login node, allocate debug node for interactive work
salloc --partition=debug --nodes=1 --time=01:00:00
srun --pty /bin/bash
```

### Running Tests

```bash
# Test basic Slurm functionality
sinfo

# Check node status
scontrol show node

# Run a test job
echo "#!/bin/bash\nsleep 60" > test.sh
chmod +x test.sh
sbatch test.sh
```

## Troubleshooting

### Common Issues

#### Cannot SSH to Login Node

**Symptoms**: Connection refused or timeout

**Solutions**:

1. Check security group rules

```bash
aws ec2 describe-security-groups --group-ids <security-group-id>
```

2. Verify allowed CIDR blocks

```bash
# Check current IP
curl ifconfig.me

# Update security group if needed
aws ec2 authorize-security-group-ingress --group-id <sg-id> --protocol tcp --port 22 --cidr <your-ip>/32
```

3. Check instance status

```bash
aws ec2 describe-instances --instance-ids <instance-id>
```

#### Slurm Services Not Starting

**Symptoms**: `sinfo` returns errors, services fail to start

**Solutions**:

1. Check Munge service

```bash
systemctl status munge
systemctl start munge
```

2. Verify Munge key

```bash
ls -la /etc/munge/munge.key
munge -n | unmunge
```

3. Check Slurm configuration

```bash
scontrol show config
tail -f /var/log/slurmctld/slurmctld.log
```

4. Verify EFS mount

```bash
df -h /shared/slurm-state
mount | grep efs
```

#### Debug Node Not Communicating with Controller

**Symptoms**: Debug node shows as DOWN in Slurm

**Solutions**:

1. Check Slurmd service

```bash
systemctl status slurmd
journalctl -u slurmd -f
```

2. Verify network connectivity

```bash
# Test connection to controller
telnet <controller-ip> 6818
```

3. Check Slurm configuration

```bash
cat /etc/slurm/slurm.conf
scontrol show config
```

#### Munge Authentication Failure

**Symptoms**: `munge -n | unmunge` fails, Slurm authentication errors

**Solutions**:

1. Restart Munge service

```bash
systemctl restart munge
systemctl status munge
```

2. Verify Munge key

```bash
# Check key file
ls -la /etc/munge/munge.key
stat /etc/munge/munge.key

# Test Munge
munge -n | unmunge
```

3. Check permissions

```bash
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
```

## Maintenance

### Updating Slurm

1. Update packages

```bash
sudo yum update -y slurm-slurmctld slurm-slurmd slurm-client
```

2. Restart services

```bash
sudo systemctl restart slurmctld slurmd
```

3. Verify configuration

```bash
scontrol show config
```

### Backing Up State

```bash
# Backup Slurm state
sudo tar -czvf /tmp/slurm-state-backup.tar.gz /var/spool/slurmctld/

# Backup configuration
sudo tar -czvf /tmp/slurm-config-backup.tar.gz /etc/slurm/
```

### Monitoring

#### CloudWatch Alarms

Monitor the following metrics:

- **EFS Burst Credits**: Alert when below 1,000,000
- **EFS Storage Utilization**: Alert when above 85%
- **EFS Throughput**: Alert when low

#### Health Checks

```bash
# Run health check
python3 /opt/hpc/scripts/controller_setup.py check-health

# Check disk space
df -h

# Check memory usage
free -h

# Check CPU usage
top
```

## Related Documentation

- [Slurm Documentation](https://slurm.schedmd.com/documentation.html)
- [Slurm Quick Reference](https://slurm.schedmd.com/quickstart.html)
- [EFS Best Practices](https://docs.aws.amazon.com/efs/latest/ug/best-practices.html)
