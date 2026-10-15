# EC2 instances, security groups, and IAM roles for login node module

locals {
  # Common tags for all resources
  common_tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
  }

  # ---------------------------------------------------------------------------
  # Login node bootstrap: client tools only (sinfo/sbatch/squeue).
  # Uses Slurm from Image Builder AMI (/opt/slurm) when present; otherwise
  # installs Munge from distro repos and waits for controller to publish a
  # shared build under /shared/software/slurm on EFS.
  # ---------------------------------------------------------------------------
  login_user_data = <<USERDATA
#!/bin/bash
exec > >(tee -a /var/log/login-init.log) 2>&1
set -x
echo "=== login bootstrap start $(date -u) ==="

PKG=$(command -v dnf >/dev/null 2>&1 && echo dnf || echo yum)

# Never fail the whole boot on a single optional step
set +e

$PKG update -y || true
# AL2023: do not install full curl (conflicts with curl-minimal)
$PKG install -y wget nfs-utils python3-pip jq amazon-efs-utils munge munge-libs \
  hwloc hwloc-libs awscli 2>/dev/null || \
$PKG install -y wget nfs-utils python3-pip jq munge hwloc hwloc-libs aws-cli || true

# Ensure SSM agent is present and running (fixes TargetNotConnected)
$PKG install -y amazon-ssm-agent 2>/dev/null || true
systemctl enable amazon-ssm-agent 2>/dev/null || true
systemctl restart amazon-ssm-agent 2>/dev/null || true

useradd -r -s /sbin/nologin slurm 2>/dev/null || true
useradd -r -s /sbin/nologin munge 2>/dev/null || true
mkdir -p /etc/slurm /opt/hpc /etc/munge /var/log/munge /var/lib/munge /run/munge
chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge || true

# --- EFS mounts (/shared required; /home optional until path exists on EFS) ---
mkdir -p /shared /home /shared/slurm-state /shared/software /shared/cluster
REGION="${data.aws_region.current.name}"
EFS_ID="${var.efs_file_system_id}"
if command -v mount.efs >/dev/null 2>&1; then
  grep -q " /shared " /etc/fstab || echo "$${EFS_ID}:/ /shared efs _netdev,tls,iam 0 0" >> /etc/fstab
  # /home is optional — create the EFS path first (controller does this) or skip
  grep -q " /home " /etc/fstab || echo "$${EFS_ID}:/home /home efs _netdev,tls,iam 0 0" >> /etc/fstab
else
  DNS="$${EFS_ID}.efs.$${REGION}.amazonaws.com"
  grep -q " /shared " /etc/fstab || echo "$${DNS}:/ /shared nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab
  grep -q " /home " /etc/fstab || echo "$${DNS}:/home /home nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab
fi
for i in 1 2 3 4 5 6 7 8 9 10; do
  mount -a && mountpoint -q /shared && break
  echo "waiting for EFS mount (attempt $i)..."
  sleep 6
done
mkdir -p /shared/slurm-state /shared/software /shared/cluster
chown -R slurm:slurm /shared/slurm-state || true

# --- Munge key from Secrets Manager (robust) ---
SECRET_ARN="${var.munge_key_secret_arn}"
mkdir -p /etc/munge /var/log/munge /var/lib/munge /run/munge
id -u munge >/dev/null 2>&1 || useradd -r -s /sbin/nologin munge || true
chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge 2>/dev/null || true
chmod 0700 /etc/munge
KEY_OK=0
for i in 1 2 3 4 5 6 7 8; do
  RAW=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --region "$REGION" --query SecretString --output text 2>/dev/null) || true
  if [ -z "$RAW" ] || [ "$RAW" = "None" ]; then echo "munge secret fetch $i failed"; sleep 5; continue; fi
  KEY=$(echo "$RAW" | jq -r '.munge_key // empty' 2>/dev/null)
  if [ -z "$KEY" ] || [ "$KEY" = "null" ]; then KEY="$RAW"; fi
  if echo "$KEY" | base64 -d > /etc/munge/munge.key.tmp 2>/dev/null && [ -s /etc/munge/munge.key.tmp ]; then
    mv /etc/munge/munge.key.tmp /etc/munge/munge.key; KEY_OK=1; break
  fi
  if [ -n "$KEY" ]; then printf '%s' "$KEY" > /etc/munge/munge.key; KEY_OK=1; break; fi
  sleep 5
done
if [ "$KEY_OK" = 1 ] && [ -s /etc/munge/munge.key ]; then
  chown munge:munge /etc/munge/munge.key
  chmod 400 /etc/munge/munge.key
  mkdir -p /run/munge; chown munge:munge /run/munge; chmod 755 /run/munge
  systemctl enable munge 2>/dev/null || true
  systemctl restart munge
  sleep 1
  systemctl is-active munge || journalctl -u munge -n 20 --no-pager || true
else
  echo "FATAL: munge key not installed on this node" >&2
fi

# --- Slurm client binaries ---
# Prefer Image Builder AMI install; never destroy a working /opt/slurm tree
setup_slurm_path() {
  if [ -x /opt/slurm/bin/sinfo ]; then
    echo 'export PATH=/opt/slurm/bin:/opt/slurm/sbin:$PATH' > /etc/profile.d/slurm.sh
    return 0
  fi
  if [ -d /opt/slurm ] && [ ! -L /opt/slurm ]; then
    rm -rf /opt/slurm
  fi
  if [ -x /shared/software/slurm/bin/sinfo ]; then
    ln -sfn /shared/software/slurm /opt/slurm
    echo 'export PATH=/opt/slurm/bin:/opt/slurm/sbin:$PATH' > /etc/profile.d/slurm.sh
    return 0
  fi
  return 1
}

if ! setup_slurm_path; then
  echo "Waiting for shared Slurm build on EFS (controller publishes /shared/software/slurm)..."
  for i in $(seq 1 60); do
    setup_slurm_path && break
    sleep 15
  done
fi
chmod 644 /etc/profile.d/slurm.sh 2>/dev/null || true
export PATH=/opt/slurm/bin:/opt/slurm/sbin:$PATH
for b in sinfo squeue sbatch scancel scontrol srun sacct; do
  [ -x "/opt/slurm/bin/$b" ] && ln -sfn "/opt/slurm/bin/$b" "/usr/local/bin/$b"
done
# Login hostname (must match Route53 login.<zone>)
LOGIN_HOST="login.${var.private_hosted_zone_name}"
LOGIN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
hostnamectl set-hostname "$${LOGIN_HOST}" 2>/dev/null || hostname "$${LOGIN_HOST}" || true
sed -i "/$${LOGIN_HOST}/d" /etc/hosts 2>/dev/null || true
sed -i '/[[:space:]]login$/d' /etc/hosts 2>/dev/null || true
if [ -n "$LOGIN_IP" ]; then
  echo "$${LOGIN_IP}  $${LOGIN_HOST} login" >> /etc/hosts
fi

# Ensure controller name resolves (Private Zone + fallback IP from TF)
CTRL_HOST="${var.project}-controller.${var.private_hosted_zone_name}"
CTRL_IP="${var.controller_instance_ip}"
if [ -n "$CTRL_IP" ]; then
  sed -i "/$${CTRL_HOST}/d" /etc/hosts 2>/dev/null || true
  echo "$${CTRL_IP}  $${CTRL_HOST} ${var.project}-controller" >> /etc/hosts
fi

# srun resolves NodeHostName (default = NodeName "debug-1"), not only NodeAddr.
# Seed /etc/hosts from EFS file published by the debug node (and keep it fresh).
ZONE_NAME="${var.private_hosted_zone_name}"
sync_debug_hosts() {
  local ip_file=/shared/cluster/debug-1.ip
  [ -s "$ip_file" ] || return 1
  local dip
  dip=$(tr -d '[:space:]' < "$ip_file")
  echo "$dip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || return 1
  sed -i '/debug-1/d' /etc/hosts 2>/dev/null || true
  echo "$dip  debug-1.$${ZONE_NAME} debug-1" >> /etc/hosts
  return 0
}
# Wait briefly in case debug boots in parallel
for _i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sync_debug_hosts && break
  sleep 5
done
# Background refresher (debug IP can change after instance replace)
cat > /usr/local/sbin/slurm-sync-debug-hosts.sh <<'SYNCEOF'
#!/bin/bash
IP_FILE=/shared/cluster/debug-1.ip
while true; do
  if [ -s "$IP_FILE" ]; then
    DIP=$(tr -d '[:space:]' < "$IP_FILE")
    if echo "$DIP" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      CUR=$(getent hosts debug-1 2>/dev/null | awk '{print $1}')
      if [ "$CUR" != "$DIP" ]; then
        sed -i '/debug-1/d' /etc/hosts 2>/dev/null || true
        echo "$DIP  debug-1.__PRIVATE_ZONE__ debug-1" >> /etc/hosts
        echo "updated /etc/hosts debug-1 -> $DIP"
      fi
    fi
  fi
  sleep 30
done
SYNCEOF
sed -i "s|__PRIVATE_ZONE__|${var.private_hosted_zone_name}|g" /usr/local/sbin/slurm-sync-debug-hosts.sh
chmod 755 /usr/local/sbin/slurm-sync-debug-hosts.sh
nohup /usr/local/sbin/slurm-sync-debug-hosts.sh >> /var/log/slurm-sync-debug-hosts.log 2>&1 &

# --- slurm.conf (client) — must match controller (no static NodeAddr) ---
cat > /etc/slurm/slurm.conf <<SLURMCONF
ClusterName=hpc-cluster
SlurmctldHost=$${CTRL_HOST}
SlurmUser=slurm
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge
CredType=cred/munge
StateSaveLocation=/shared/slurm-state
SlurmdSpoolDir=/var/spool/slurmd
SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmdPidFile=/var/run/slurm/slurmd.pid
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
MailProg=/bin/true
# Default none so login never depends on dead :6819. Upgrade if controller published slurmdbd.
AccountingStorageType=accounting_storage/none
JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=30
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_CPU
PartitionName=debug Priority=50 Default=YES MaxTime=24:00:00 State=UP Nodes=debug-1
PartitionName=std Priority=40 Default=NO MaxTime=7-00:00:00 State=UP Nodes=std-[1-3]
NodeName=debug-1 CPUs=2 RealMemory=800 State=UNKNOWN
NodeName=std-[1-3] CPUs=2 RealMemory=800 State=CLOUD
SuspendTime=300
ReturnToService=1
SLURMCONF
chown -R slurm:slurm /etc/slurm 2>/dev/null || true
chmod 644 /etc/slurm/slurm.conf
# Match controller accounting mode when available (written to EFS by controller)
if [ -f /shared/cluster/accounting_mode ] && grep -qx slurmdbd /shared/cluster/accounting_mode; then
  sed -i 's|^AccountingStorageType=.*|AccountingStorageType=accounting_storage/slurmdbd|' /etc/slurm/slurm.conf
  grep -q '^AccountingStorageHost=' /etc/slurm/slurm.conf || echo "AccountingStorageHost=$${CTRL_HOST}" >> /etc/slurm/slurm.conf
  sed -i "s|^AccountingStorageHost=.*|AccountingStorageHost=$${CTRL_HOST}|" /etc/slurm/slurm.conf
  grep -q '^AccountingStoragePort=' /etc/slurm/slurm.conf || echo 'AccountingStoragePort=6819' >> /etc/slurm/slurm.conf
  sed -i 's|^AccountingStoragePort=.*|AccountingStoragePort=6819|' /etc/slurm/slurm.conf
fi

# seff (job efficiency) — needs accounting; install minimal wrapper if missing
# Always install Python seff (Perl SchedMD seff needs Slurmdb.pm)
if true; then
  cat > /usr/local/bin/seff <<'SEFFEOF'
#!/usr/bin/env python3
import sys, subprocess
if len(sys.argv) < 2:
    print("Usage: seff <jobid>", file=sys.stderr); sys.exit(1)
jid = sys.argv[1]
fmt = "JobID,JobName,State,Elapsed,TotalCPU,AllocCPUS,ReqMem,MaxRSS,AveRSS,NodeList"
out = subprocess.run(["sacct", "-j", jid, "-n", "-P", f"--format={fmt}"],
                     capture_output=True, text=True)
if out.returncode != 0 or not out.stdout.strip():
    print(out.stderr or "No accounting data (enable slurmdbd/MariaDB)", file=sys.stderr)
    sys.exit(1)
print(f"Job efficiency for {jid}:")
for line in out.stdout.strip().splitlines():
    print(" ", line.replace("|", "  "))
SEFFEOF
  chmod 755 /usr/local/bin/seff
fi
# Prefer Python wrapper over broken Perl contrib seff
ln -sfn /usr/local/bin/seff /opt/slurm/bin/seff 2>/dev/null || true

# Client-side cgroup.conf (harmless; keeps configs consistent)
cat > /etc/slurm/cgroup.conf <<'EOF'
CgroupPlugin=cgroup/v1
CgroupAutomount=yes
ConstrainCores=no
ConstrainRAMSpace=no
ConstrainDevices=no
EOF
chown slurm:slurm /etc/slurm/cgroup.conf 2>/dev/null || true
chmod 644 /etc/slurm/cgroup.conf

# Symlink client tools into /usr/local/bin for non-login shells
for b in sinfo squeue sbatch scancel scontrol srun sacct; do
  if [ -x "/opt/slurm/bin/$b" ]; then
    ln -sfn "/opt/slurm/bin/$b" "/usr/local/bin/$b"
  fi
done

# --- Cluster SSH key (shared via EFS; public key authorized for ec2-user) ---
mkdir -p /home/ec2-user/.ssh /shared/cluster
chmod 700 /home/ec2-user/.ssh
# Wait briefly for controller to publish cluster key
for i in 1 2 3 4 5 6 7 8 9 10; do
  if [ -f /shared/cluster/id_ed25519.pub ]; then
    touch /home/ec2-user/.ssh/authorized_keys
    grep -qf /shared/cluster/id_ed25519.pub /home/ec2-user/.ssh/authorized_keys 2>/dev/null ||       cat /shared/cluster/id_ed25519.pub >> /home/ec2-user/.ssh/authorized_keys
    if [ -f /shared/cluster/id_ed25519 ]; then
      cp /shared/cluster/id_ed25519 /home/ec2-user/.ssh/id_ed25519
      chmod 600 /home/ec2-user/.ssh/id_ed25519
      chown ec2-user:ec2-user /home/ec2-user/.ssh/id_ed25519
    fi
    break
  fi
  sleep 6
done
chmod 600 /home/ec2-user/.ssh/authorized_keys 2>/dev/null || true
chown -R ec2-user:ec2-user /home/ec2-user/.ssh 2>/dev/null || true
# SSH client config for private nodes
cat > /home/ec2-user/.ssh/config <<'SSHCFG'
Host 10.0.* *.hpc.internal
  User ec2-user
  IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ~/.ssh/known_hosts
SSHCFG
chown ec2-user:ec2-user /home/ec2-user/.ssh/config
chmod 600 /home/ec2-user/.ssh/config

# --- Optional YAML user provisioning ---
pip3 install --quiet pyyaml 2>/dev/null || true
cat > /opt/hpc/users.yaml <<'USERSYAML'
${var.users_yaml_content}
USERSYAML
python3 - <<'PYUSERS' || true
import os, pwd, subprocess, yaml, pathlib
path = pathlib.Path("/opt/hpc/users.yaml")
if not path.exists() or not path.read_text().strip():
    raise SystemExit(0)
try:
    data = yaml.safe_load(path.read_text()) or {}
except Exception:
    raise SystemExit(0)
for u in data.get("users") or []:
    name = u.get("name")
    if not name:
        continue
    uid = u.get("uid")
    groups = u.get("groups") or []
    shell = u.get("shell", "/bin/bash")
    home = u.get("home", f"/home/{name}")
    try:
        pwd.getpwnam(name)
    except KeyError:
        cmd = ["useradd", "-m", "-s", shell, "-d", home]
        if uid is not None:
            cmd += ["-u", str(uid)]
        cmd.append(name)
        subprocess.run(cmd, check=False)
    for g in groups:
        subprocess.run(["groupadd", "-f", g], check=False)
        subprocess.run(["usermod", "-aG", g, name], check=False)
    keys = u.get("ssh_keys") or []
    if keys:
        ssh_dir = pathlib.Path(home) / ".ssh"
        ssh_dir.mkdir(parents=True, exist_ok=True)
        ak = ssh_dir / "authorized_keys"
        existing = ak.read_text() if ak.exists() else ""
        with ak.open("a") as f:
            for k in keys:
                if k and k not in existing:
                    f.write(k.strip() + "\n")
        subprocess.run(["chown", "-R", f"{name}:{name}", str(ssh_dir)], check=False)
        os.chmod(ssh_dir, 0o700)
        os.chmod(ak, 0o600)
print("user provisioning complete")
PYUSERS

echo "=== login bootstrap done $(date -u) ==="
command -v sinfo && sinfo -V || echo "sinfo not yet available (controller may still be building Slurm)"
USERDATA

  # ---------------------------------------------------------------------------
  # Debug node bootstrap: slurmd only
  # ---------------------------------------------------------------------------
  debug_user_data = <<USERDATA
#!/bin/bash
exec > >(tee -a /var/log/debug-init.log) 2>&1
set -x
echo "=== debug bootstrap start $(date -u) ==="

PKG=$(command -v dnf >/dev/null 2>&1 && echo dnf || echo yum)
set +e

$PKG update -y || true
# AL2023: no full curl; hwloc required for slurmd (linked at Slurm build time)
$PKG install -y wget nfs-utils python3-pip jq amazon-efs-utils munge munge-libs \
  hwloc hwloc-libs awscli 2>/dev/null || \
$PKG install -y wget nfs-utils python3-pip jq munge hwloc hwloc-libs aws-cli || true
$PKG install -y amazon-ssm-agent 2>/dev/null || true
systemctl enable amazon-ssm-agent 2>/dev/null || true
systemctl restart amazon-ssm-agent 2>/dev/null || true

useradd -r -s /sbin/nologin slurm 2>/dev/null || true
useradd -r -s /sbin/nologin munge 2>/dev/null || true
mkdir -p /var/spool/slurmd /etc/slurm /opt/hpc /etc/munge /var/log/munge /var/lib/munge /run/munge /var/log/slurm /var/run/slurm
chown -R slurm:slurm /var/spool/slurmd /var/log/slurm /var/run/slurm || true
chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge || true

# EFS — /shared is required; /home is optional (path may not exist yet on EFS)
mkdir -p /shared /home /shared/slurm-state /shared/software /shared/cluster
REGION="${data.aws_region.current.name}"
EFS_ID="${var.efs_file_system_id}"
if command -v mount.efs >/dev/null 2>&1; then
  grep -q " /shared " /etc/fstab || echo "$${EFS_ID}:/ /shared efs _netdev,tls,iam 0 0" >> /etc/fstab
  grep -q " /home " /etc/fstab || echo "$${EFS_ID}:/home /home efs _netdev,tls,iam 0 0" >> /etc/fstab
else
  DNS="$${EFS_ID}.efs.$${REGION}.amazonaws.com"
  grep -q " /shared " /etc/fstab || echo "$${DNS}:/ /shared nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab
  grep -q " /home " /etc/fstab || echo "$${DNS}:/home /home nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab
fi
for i in 1 2 3 4 5 6 7 8 9 10; do
  # Only require /shared; ignore /home failures (ENOENT until path is created)
  mount /shared 2>/dev/null || mount -a 2>/dev/null || true
  mountpoint -q /shared && break
  sleep 6
done
# Best-effort /home (do not block bootstrap)
mount /home 2>/dev/null || true
mkdir -p /shared/slurm-state /shared/software /shared/cluster
chown -R slurm:slurm /shared/slurm-state || true

# Munge key from Secrets Manager (robust)
SECRET_ARN="${var.munge_key_secret_arn}"
mkdir -p /etc/munge /var/log/munge /var/lib/munge /run/munge
id -u munge >/dev/null 2>&1 || useradd -r -s /sbin/nologin munge || true
chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge 2>/dev/null || true
chmod 0700 /etc/munge
KEY_OK=0
for i in 1 2 3 4 5 6 7 8; do
  RAW=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --region "$REGION" --query SecretString --output text 2>/dev/null) || true
  if [ -z "$RAW" ] || [ "$RAW" = "None" ]; then echo "munge secret fetch $i failed"; sleep 5; continue; fi
  KEY=$(echo "$RAW" | jq -r '.munge_key // empty' 2>/dev/null)
  if [ -z "$KEY" ] || [ "$KEY" = "null" ]; then KEY="$RAW"; fi
  if echo "$KEY" | base64 -d > /etc/munge/munge.key.tmp 2>/dev/null && [ -s /etc/munge/munge.key.tmp ]; then
    mv /etc/munge/munge.key.tmp /etc/munge/munge.key; KEY_OK=1; break
  fi
  if [ -n "$KEY" ]; then printf '%s' "$KEY" > /etc/munge/munge.key; KEY_OK=1; break; fi
  sleep 5
done
if [ "$KEY_OK" = 1 ] && [ -s /etc/munge/munge.key ]; then
  chown munge:munge /etc/munge/munge.key
  chmod 400 /etc/munge/munge.key
  mkdir -p /run/munge; chown munge:munge /run/munge; chmod 755 /run/munge
  systemctl enable munge 2>/dev/null || true
  systemctl restart munge
  sleep 1
  systemctl is-active munge || journalctl -u munge -n 20 --no-pager || true
else
  echo "FATAL: munge key not installed on debug node" >&2
fi

# Slurm binaries — prefer AMI /opt/slurm; never destroy a working AMI tree
setup_slurm_path() {
  if [ -x /opt/slurm/sbin/slurmd ]; then
    echo 'export PATH=/opt/slurm/bin:/opt/slurm/sbin:$PATH' > /etc/profile.d/slurm.sh
    return 0
  fi
  if [ -d /opt/slurm ] && [ ! -L /opt/slurm ]; then
    # Broken/empty directory only — safe to remove
    rm -rf /opt/slurm
  fi
  if [ -x /shared/software/slurm/sbin/slurmd ]; then
    ln -sfn /shared/software/slurm /opt/slurm
    echo 'export PATH=/opt/slurm/bin:/opt/slurm/sbin:$PATH' > /etc/profile.d/slurm.sh
    return 0
  fi
  return 1
}
if ! setup_slurm_path; then
  for i in $(seq 1 60); do
    setup_slurm_path && break
    sleep 15
  done
fi
export PATH=/opt/slurm/bin:/opt/slurm/sbin:$PATH
for b in sinfo squeue sbatch scancel scontrol srun sacct; do
  [ -x "/opt/slurm/bin/$b" ] && ln -sfn "/opt/slurm/bin/$b" "/usr/local/bin/$b"
done
ldconfig || true

# Identity must match NodeName=debug-1
hostnamectl set-hostname "debug-1.${var.private_hosted_zone_name}" 2>/dev/null || hostname "debug-1.${var.private_hosted_zone_name}" || true
DEBUG_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
sed -i '/debug-1/d' /etc/hosts 2>/dev/null || true
echo "$${DEBUG_IP}  debug-1.${var.private_hosted_zone_name} debug-1" >> /etc/hosts

# Publish current IP for controller registration (survives instance replace / new private IP)
mkdir -p /shared/cluster
echo "$${DEBUG_IP}" > /shared/cluster/debug-1.ip
chmod 644 /shared/cluster/debug-1.ip

CTRL_HOST="${var.project}-controller.${var.private_hosted_zone_name}"
CTRL_IP="${var.controller_instance_ip}"
if [ -n "$CTRL_IP" ]; then
  sed -i "/$${CTRL_HOST}/d" /etc/hosts 2>/dev/null || true
  echo "$${CTRL_IP}  $${CTRL_HOST} ${var.project}-controller" >> /etc/hosts
fi

mkdir -p /var/run/slurm
chown slurm:slurm /var/run/slurm

cat > /etc/slurm/slurm.conf <<SLURMCONF
ClusterName=hpc-cluster
SlurmctldHost=$${CTRL_HOST}
SlurmUser=slurm
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge
CredType=cred/munge
StateSaveLocation=/shared/slurm-state
SlurmdSpoolDir=/var/spool/slurmd
SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmdPidFile=/var/run/slurm/slurmd.pid
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
MailProg=/bin/true
# Default none; promote only if controller published slurmdbd mode on EFS
AccountingStorageType=accounting_storage/none
JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=30
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_CPU
PartitionName=debug Priority=50 Default=YES MaxTime=24:00:00 State=UP Nodes=debug-1
PartitionName=std Priority=40 Default=NO MaxTime=7-00:00:00 State=UP Nodes=std-[1-3]
NodeName=debug-1 NodeAddr=$${DEBUG_IP} CPUs=2 RealMemory=800 State=UNKNOWN
NodeName=std-[1-3] CPUs=2 RealMemory=800 State=CLOUD
SuspendTime=300
ReturnToService=1
SLURMCONF
chown -R slurm:slurm /etc/slurm
chmod 644 /etc/slurm/slurm.conf
if [ -f /shared/cluster/accounting_mode ] && grep -qx slurmdbd /shared/cluster/accounting_mode; then
  sed -i 's|^AccountingStorageType=.*|AccountingStorageType=accounting_storage/slurmdbd|' /etc/slurm/slurm.conf
  grep -q '^AccountingStorageHost=' /etc/slurm/slurm.conf || echo "AccountingStorageHost=$${CTRL_HOST}" >> /etc/slurm/slurm.conf
  sed -i "s|^AccountingStorageHost=.*|AccountingStorageHost=$${CTRL_HOST}|" /etc/slurm/slurm.conf
  grep -q '^AccountingStoragePort=' /etc/slurm/slurm.conf || echo 'AccountingStoragePort=6819' >> /etc/slurm/slurm.conf
  sed -i 's|^AccountingStoragePort=.*|AccountingStoragePort=6819|' /etc/slurm/slurm.conf
fi

# AMI only ships cgroup/v1 plugin — force it (default cgroup/v2 fails on this build)
cat > /etc/slurm/cgroup.conf <<'EOF'
CgroupPlugin=cgroup/v1
CgroupAutomount=yes
ConstrainCores=no
ConstrainRAMSpace=no
ConstrainDevices=no
EOF
chown slurm:slurm /etc/slurm/cgroup.conf
chmod 644 /etc/slurm/cgroup.conf

# slurmd unit (always refresh so path is correct)
cat >/usr/lib/systemd/system/slurmd.service <<'EOF'
[Unit]
Description=Slurm compute node daemon
After=network-online.target munge.service
Wants=network-online.target
Requires=munge.service
[Service]
Type=simple
Environment=LD_LIBRARY_PATH=/opt/slurm/lib
ExecStart=/opt/slurm/sbin/slurmd -D
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
if [ -x /opt/slurm/sbin/slurmd ] && systemctl is-active --quiet munge; then
  systemctl enable slurmd 2>/dev/null || true
  systemctl restart slurmd 2>/dev/null || true
  sleep 2
  systemctl is-active slurmd || journalctl -u slurmd -n 30 --no-pager || true
else
  echo "Skip slurmd start (binary or munge missing)"
  ldd /opt/slurm/sbin/slurmd 2>/dev/null | grep -E 'not found|hwloc' || true
fi

# Best-effort: push NodeAddr to controller (also done by controller watching EFS file)
export PATH=/opt/slurm/bin:/opt/slurm/sbin:$PATH
if [ -n "$DEBUG_IP" ] && command -v scontrol >/dev/null 2>&1; then
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    scontrol update NodeName=debug-1 NodeAddr="$DEBUG_IP" 2>/dev/null && break
    sleep 10
  done
fi

# Cluster SSH authorized key
mkdir -p /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh
for i in 1 2 3 4 5 6 7 8 9 10; do
  if [ -f /shared/cluster/id_ed25519.pub ]; then
    touch /home/ec2-user/.ssh/authorized_keys
    grep -qf /shared/cluster/id_ed25519.pub /home/ec2-user/.ssh/authorized_keys 2>/dev/null ||       cat /shared/cluster/id_ed25519.pub >> /home/ec2-user/.ssh/authorized_keys
    break
  fi
  sleep 6
done
chmod 600 /home/ec2-user/.ssh/authorized_keys 2>/dev/null || true
chown -R ec2-user:ec2-user /home/ec2-user/.ssh 2>/dev/null || true

echo "=== debug bootstrap done $(date -u) ==="
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
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Effect   = "Allow"
        Resource = var.munge_key_secret_arn
      },
      {
        # CMK-encrypted secrets require kms:Decrypt
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Effect   = "Allow"
        Resource = try(var.kms_key_arns["secrets_manager"], "*")
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
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

# Session Manager (required for aws ssm start-session; avoids TargetNotConnected)
resource "aws_iam_role_policy_attachment" "login_ssm_core" {
  count      = var.create_login_node ? 1 : 0
  role       = aws_iam_role.login_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EFS IAM mount (ClientMount/ClientWrite when using mount.efs + iam)
resource "aws_iam_role_policy" "login_efs_client" {
  count = var.create_login_node ? 1 : 0
  name  = "${var.project}-${var.env}-${var.session}-login-efs-client"
  role  = aws_iam_role.login_node[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess"
      ]
      Resource = "*"
    }]
  })
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
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Effect   = "Allow"
        Resource = var.munge_key_secret_arn
      },
      {
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Effect   = "Allow"
        Resource = try(var.kms_key_arns["secrets_manager"], "*")
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
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

resource "aws_iam_role_policy_attachment" "debug_ssm_core" {
  count      = var.create_debug_node ? 1 : 0
  role       = aws_iam_role.debug_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "debug_efs_client" {
  count = var.create_debug_node ? 1 : 0
  name  = "${var.project}-${var.env}-${var.session}-debug-efs-client"
  role  = aws_iam_role.debug_node[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess"
      ]
      Resource = "*"
    }]
  })
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

  # Slurm client traffic / replies from controller and debug (ephemeral + control ports)
  ingress {
    description = "Slurmctld/slurmd from VPC"
    from_port   = 6817
    to_port     = 6818
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Ephemeral TCP from VPC (debug may reply on high ports)"
    from_port   = 1024
    to_port     = 65535
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

  # Slurm slurmd from controller (and login for diagnostics)
  ingress {
    description     = "Slurm slurmd from controller SG"
    from_port       = 6818
    to_port         = 6818
    protocol        = "tcp"
    security_groups = try([var.security_group_ids["controller"]], [])
  }

  ingress {
    description     = "Slurm slurmd from login node"
    from_port       = 6818
    to_port         = 6818
    protocol        = "tcp"
    security_groups = [aws_security_group.login_node[0].id]
  }

  # Ephemeral ports from controller/login (srun, replies, high-port clients)
  ingress {
    description = "Ephemeral TCP from VPC (controller/login high-port traffic)"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # SSH also from controller (ops / cluster key hops)
  ingress {
    description     = "SSH from controller SG"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = try([var.security_group_ids["controller"]], [])
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
  key_name               = var.ssh_key_name != "" ? var.ssh_key_name : null

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

  # User data for bootstrapping (includes EFS mounts + user provisioning)
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

  user_data_replace_on_change = true

  lifecycle {
    # Allow AMI updates from make ami-build / promote to roll instances
    create_before_destroy = true
  }
}

# =============================================================================
# Debug Node EC2 Instance
# =============================================================================

resource "aws_instance" "debug_node" {
  count = var.create_debug_node ? 1 : 0

  ami           = var.ami_id
  instance_type = var.debug_instance_type
  subnet_id     = var.private_subnet_ids[0]
  # debug_node SG + network compute SG so controller rules that key off compute tier apply
  vpc_security_group_ids = compact([
    aws_security_group.debug_node[0].id,
    try(var.security_group_ids["compute"], null),
  ])
  iam_instance_profile = aws_iam_instance_profile.debug_node[0].name
  key_name             = var.ssh_key_name != "" ? var.ssh_key_name : null

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

  # User data for bootstrapping (includes EFS mounts + slurmd)
  user_data = local.debug_user_data

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-debug"
    Role = "debug"
    Type = "static"
    NodeName = "debug-1"
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  user_data_replace_on_change = true

  lifecycle {
    # Allow AMI updates from make ami-build / promote to roll instances
    create_before_destroy = true
  }
}

# =============================================================================
# Route 53 private DNS records
# =============================================================================

resource "aws_route53_record" "login" {
  count = var.create_login_node ? 1 : 0

  zone_id = var.private_hosted_zone_id
  name    = "login.${var.private_hosted_zone_name}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.login_node[0].private_ip]
}

resource "aws_route53_record" "debug" {
  count = var.create_debug_node ? 1 : 0

  zone_id = var.private_hosted_zone_id
  name    = "debug-1.${var.private_hosted_zone_name}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.debug_node[0].private_ip]
}
