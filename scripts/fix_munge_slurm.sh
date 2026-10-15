#!/bin/bash
# Run on EACH node (controller, login, debug) via SSM as root/ssm-user with sudo.
# Fixes munge key + starts munge and role-appropriate Slurm services.
set -x

REGION="${AWS_REGION:-us-east-1}"
# Discover secret by name prefix if ARN not provided
if [ -z "$SECRET_ARN" ]; then
  SECRET_ARN=$(aws secretsmanager list-secrets --region "$REGION" \
    --query "SecretList[?contains(Name, \`munge-key\`)].ARN | [0]" --output text 2>/dev/null)
fi
echo "SECRET_ARN=$SECRET_ARN"

mkdir -p /etc/munge /var/log/munge /var/lib/munge /run/munge
id -u munge >/dev/null 2>&1 || useradd -r -s /sbin/nologin munge || true
chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge || true
chmod 0700 /etc/munge

if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "None" ]; then
  echo "ERROR: set SECRET_ARN to the munge-key secret ARN"
  exit 1
fi

RAW=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --region "$REGION" --query SecretString --output text)
KEY=$(echo "$RAW" | jq -r '.munge_key // empty')
[ -z "$KEY" ] || [ "$KEY" = "null" ] && KEY="$RAW"

if echo "$KEY" | base64 -d > /etc/munge/munge.key.tmp 2>/dev/null && [ -s /etc/munge/munge.key.tmp ]; then
  mv /etc/munge/munge.key.tmp /etc/munge/munge.key
else
  printf '%s' "$KEY" > /etc/munge/munge.key
fi

chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
ls -la /etc/munge/munge.key
mkdir -p /run/munge && chown munge:munge /run/munge && chmod 755 /run/munge

systemctl enable munge
systemctl restart munge
sleep 1
systemctl status munge --no-pager || journalctl -u munge -n 40 --no-pager

# PATH / symlinks for AMI-installed Slurm
if [ -d /opt/slurm/bin ]; then
  echo 'export PATH=/opt/slurm/bin:/opt/slurm/sbin:$PATH' > /etc/profile.d/slurm.sh
  for b in sinfo squeue sbatch scancel scontrol srun sacct; do
    [ -x "/opt/slurm/bin/$b" ] && ln -sfn "/opt/slurm/bin/$b" "/usr/local/bin/$b"
  done
  ls -la /opt/slurm/bin | head
else
  echo "WARNING: /opt/slurm not present — AMI may not have Slurm; check Image Builder build"
fi

# Write minimal slurm.conf if missing (controller hostname via DNS)
if [ ! -f /etc/slurm/slurm.conf ]; then
  mkdir -p /etc/slurm /var/log/slurm /var/spool/slurmctld /var/spool/slurmd
  CTRL=$(getent hosts controller 2>/dev/null | awk '{print $1}')
  # Prefer internal DNS names from this testbed
  CTRL_HOST=$(ls /etc/slurm 2>/dev/null; hostname -f)
  cat > /etc/slurm/slurm.conf <<EOF
ClusterName=hpc-cluster
SlurmctldHost=$(hostname -f)
SlurmUser=slurm
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge
CredType=cred/munge
StateSaveLocation=/shared/slurm-state
SlurmdSpoolDir=/var/spool/slurmd
AccountingStorageType=accounting_storage/none
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_CPU
PartitionName=debug Priority=50 Default=YES MaxTime=24:00:00 State=UP Nodes=debug-1
NodeName=debug-1 CPUs=2 State=UNKNOWN
EOF
  id -u slurm >/dev/null 2>&1 || useradd -r -s /sbin/nologin slurm || true
  chown -R slurm:slurm /etc/slurm /var/spool/slurmctld /var/spool/slurmd /var/log/slurm /shared/slurm-state 2>/dev/null || true
fi

ROLE=$(hostname)
# Start daemons based on what units exist / role tag is hard; try both safely
if [ -x /opt/slurm/sbin/slurmctld ] && systemctl is-active --quiet munge; then
  # Only controller should run slurmctld — detect by private DNS name pattern
  if hostname | grep -qi controller || [ -f /var/log/controller-init.log ]; then
    systemctl enable slurmctld 2>/dev/null || true
    systemctl restart slurmctld 2>/dev/null || true
    systemctl status slurmctld --no-pager || true
  fi
fi
if [ -x /opt/slurm/sbin/slurmd ] && systemctl is-active --quiet munge; then
  if hostname | grep -qiE 'debug|ip-10-0-100' || [ -f /var/log/debug-init.log ]; then
    # Only start slurmd on compute/debug (not pure login)
    if [ -f /var/log/debug-init.log ] || hostname | grep -qi debug; then
      systemctl enable slurmd 2>/dev/null || true
      systemctl restart slurmd 2>/dev/null || true
      systemctl status slurmd --no-pager || true
    fi
  fi
fi

command -v sinfo && sinfo -V || echo "sinfo still missing"
systemctl is-active munge
echo "done on $(hostname)"
