# Controller module: Slurm controller (slurmctld + slurmdbd), Munge, optional MariaDB

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

locals {
  common_tags = {
    Project = var.project
    Env     = var.env
    Session = var.session
  }

  # RDS endpoint (empty when MariaDB disabled). Forward-ref to resource below is OK.
  mariadb_host = var.enable_mariadb ? try(aws_db_instance.mariadb[0].address, "") : ""
  mariadb_port = var.enable_mariadb ? tostring(try(aws_db_instance.mariadb[0].port, 3306)) : "3306"

  controller_user_data = <<-USERDATA
#!/bin/bash
exec > >(tee -a /var/log/controller-init.log) 2>&1
set -x
echo "=== controller bootstrap start $(date -u) ==="

PKG=$(command -v dnf >/dev/null 2>&1 && echo dnf || echo yum)
set +e

# AL2023 ships curl-minimal; do NOT install full curl (conflicts). Use wget.
$PKG update -y || true
$PKG install -y --setopt=install_weak_deps=False \
  wget nfs-utils jq python3 python3-pip amazon-efs-utils \
  munge munge-libs munge-devel hwloc hwloc-libs hwloc-devel \
  gcc gcc-c++ make automake autoconf libtool \
  openssl-devel pam-devel numactl-devel bzip2 tar \
  amazon-ssm-agent 2>/dev/null || \
$PKG install -y wget nfs-utils jq python3 munge gcc gcc-c++ make \
  openssl-devel bzip2 tar hwloc hwloc-libs 2>/dev/null || true
# AL2023 MariaDB client + headers for slurmdbd (accounting_storage/mysql)
$PKG install -y mariadb105 mariadb105-devel 2>/dev/null || \
  $PKG install -y mariadb1011 mariadb1011-devel 2>/dev/null || true
command -v mysql_config || ls /usr/bin/mysql_config 2>/dev/null || true

# Ensure compiler present (required for EFS fallback Slurm build)
if ! command -v gcc >/dev/null 2>&1; then
  $PKG install -y --allowerasing gcc gcc-c++ make automake autoconf \
    openssl-devel pam-devel numactl-devel hwloc-devel bzip2 tar wget || true
fi
command -v gcc && gcc --version | head -1

systemctl enable amazon-ssm-agent 2>/dev/null || true
systemctl restart amazon-ssm-agent 2>/dev/null || true

# AL2023 may not ship munge RPMs — build from source if package missing
if ! rpm -q munge >/dev/null 2>&1 && ! command -v munged >/dev/null 2>&1; then
  echo "munge package not found; building from source..."
  $PKG install -y gcc make openssl-devel bzip2 tar wget xz || true
  cd /tmp
  MVER=0.5.15
  wget -q "https://github.com/dun/munge/releases/download/munge-$${MVER}/munge-$${MVER}.tar.xz" || \
    curl -fsSL -o "munge-$${MVER}.tar.xz" "https://github.com/dun/munge/releases/download/munge-$${MVER}/munge-$${MVER}.tar.xz"
  tar -xf "munge-$${MVER}.tar.xz"
  cd "munge-$${MVER}"
  ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --runstatedir=/run
  make -j2 && make install
  ldconfig || true
  useradd -r -s /sbin/nologin munge 2>/dev/null || true
  mkdir -p /etc/munge /var/log/munge /var/lib/munge /run/munge
  chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge
  cat >/usr/lib/systemd/system/munge.service <<'MEOF'
[Unit]
Description=MUNGE authentication service
After=network.target
[Service]
Type=forking
ExecStart=/usr/sbin/munged
User=munge
Group=munge
Restart=on-failure
[Install]
WantedBy=multi-user.target
MEOF
  systemctl daemon-reload
fi

useradd -r -s /sbin/nologin slurm 2>/dev/null || true
useradd -r -s /sbin/nologin munge 2>/dev/null || true
# Do NOT mkdir /opt/slurm here — it must be a symlink to EFS or AMI path (ln -sfn fails if dir exists)
mkdir -p /shared /home /shared/slurm-state /shared/software /shared/cluster \
  /var/spool/slurmctld /var/spool/slurmd /etc/slurm /etc/munge /var/log/munge /var/lib/munge /run/munge /var/log/slurm \
  /var/run/slurm /run/slurm
chown -R slurm:slurm /var/spool/slurmctld /var/spool/slurmd /var/log/slurm /var/run/slurm /run/slurm || true
chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge || true

REGION="${data.aws_region.current.name}"
EFS_ID="${var.efs_file_system_id}"
# Prefer NFS (works without amazon-efs-utils); IAM/tls efs helper is optional
DNS="$${EFS_ID}.efs.$${REGION}.amazonaws.com"
# Ensure mountpoint is empty local dir (not already a real mount)
if ! mountpoint -q /shared; then
  rm -rf /shared
  mkdir -p /shared
fi
grep -q " /shared " /etc/fstab || echo "$${DNS}:/ /shared nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  mount /shared 2>/dev/null || mount -a
  if mountpoint -q /shared && ! df -h /shared | grep -q nvme; then
    echo "EFS mounted on /shared"
    break
  fi
  echo "waiting for EFS NFS (attempt $i) DNS=$${DNS}"
  sleep 8
done
if ! mountpoint -q /shared || df -h /shared 2>/dev/null | grep -q nvme; then
  echo "ERROR: EFS mount failed — check SG 2049, mount targets, NAT/DNS" | tee -a /var/log/controller-init.log
fi
# Create EFS top-level paths. /shared is the EFS root, so /shared/home == EFS:/home
# (required so login/debug can mount fs-xxx:/home -> /home without ENOENT)
mkdir -p /shared/slurm-state /shared/software /shared/cluster /shared/home
chown -R slurm:slurm /shared/slurm-state || true

# Munge key from Secrets Manager (robust)
SECRET_ARN="${aws_secretsmanager_secret.munge_key.arn}"
REGION="${data.aws_region.current.name}"
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
  echo "FATAL: munge key not installed" >&2
fi

# Cluster SSH key for login <-> private nodes (published on EFS)
if [ ! -f /shared/cluster/id_ed25519 ]; then
  ssh-keygen -t ed25519 -N "" -f /shared/cluster/id_ed25519 -C "hpc-cluster" || \
    ssh-keygen -t rsa -b 2048 -N "" -f /shared/cluster/id_ed25519 -C "hpc-cluster"
  chmod 600 /shared/cluster/id_ed25519
  chmod 644 /shared/cluster/id_ed25519.pub
fi
mkdir -p /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh
cp /shared/cluster/id_ed25519 /home/ec2-user/.ssh/id_ed25519
cp /shared/cluster/id_ed25519.pub /home/ec2-user/.ssh/id_ed25519.pub
touch /home/ec2-user/.ssh/authorized_keys
grep -qf /shared/cluster/id_ed25519.pub /home/ec2-user/.ssh/authorized_keys 2>/dev/null || \
  cat /shared/cluster/id_ed25519.pub >> /home/ec2-user/.ssh/authorized_keys
chmod 600 /home/ec2-user/.ssh/id_ed25519 /home/ec2-user/.ssh/authorized_keys
chown -R ec2-user:ec2-user /home/ec2-user/.ssh

# Install Slurm: prefer AMI /opt/slurm; else build once and publish to EFS
SLURM_VERSION="${var.slurm_version}"
link_opt_slurm() {
  # Prefer a working AMI install under /opt/slurm. Only replace with the EFS
  # build when AMI binaries are missing. Never rm -rf a working AMI tree.
  if [ -x /opt/slurm/sbin/slurmctld ] || [ -x /opt/slurm/bin/sinfo ]; then
    return 0
  fi
  if [ -d /opt/slurm ] && [ ! -L /opt/slurm ]; then
    # Empty or broken directory left by a previous failed attempt — safe to remove
    rm -rf /opt/slurm
  fi
  if [ -x /shared/software/slurm/sbin/slurmctld ] || [ -x /shared/software/slurm/bin/sinfo ]; then
    ln -sfn /shared/software/slurm /opt/slurm
  fi
}
has_mysql_acct_plugin() {
  # accounting_storage/mysql is required for slurmdbd → RDS
  [ -f /opt/slurm/lib/slurm/accounting_storage_mysql.so ] \
    || [ -f /opt/slurm/lib64/slurm/accounting_storage_mysql.so ] \
    || [ -f /shared/software/slurm/lib/slurm/accounting_storage_mysql.so ] \
    || [ -f /shared/software/slurm/lib64/slurm/accounting_storage_mysql.so ]
}
install_slurm() {
  NEED_MYSQL="${var.enable_mariadb}"
  if [ -x /opt/slurm/sbin/slurmctld ] && [ -x /opt/slurm/bin/sinfo ]; then
    if [ "$NEED_MYSQL" != "true" ] || has_mysql_acct_plugin; then
      echo "Using Slurm from AMI /opt/slurm (mysql plugin ok or not required)"
      has_mysql_acct_plugin && ls -la /opt/slurm/lib*/slurm/accounting_storage_mysql.so 2>/dev/null || true
      return 0
    fi
    echo "AMI Slurm lacks accounting_storage/mysql — rebuilding with MariaDB support"
  elif [ -x /shared/software/slurm/sbin/slurmctld ] && [ -x /shared/software/slurm/bin/sinfo ]; then
    link_opt_slurm
    if [ "$NEED_MYSQL" != "true" ] || has_mysql_acct_plugin; then
      echo "Using shared EFS Slurm build"
      return 0
    fi
    echo "EFS Slurm lacks accounting_storage/mysql — rebuilding"
  fi
  if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
    echo "FATAL: gcc/make missing — cannot build Slurm" >&2
    return 1
  fi
  # HARD REQUIRE mysql_config when accounting is enabled
  if ! command -v mysql_config >/dev/null 2>&1; then
    $PKG install -y mariadb105 mariadb105-devel \
      || $PKG install -y mariadb1011 mariadb1011-devel \
      || {
        echo "FATAL: cannot install mariadb*-devel (needed for slurmdbd)" >&2
        return 1
      }
  fi
  if ! command -v mysql_config >/dev/null 2>&1; then
    echo "FATAL: mysql_config missing after mariadb*-devel install" >&2
    return 1
  fi
  mysql_config --version || true
  echo "Building Slurm $${SLURM_VERSION} with MySQL (10–20 min on small instances)..."
  cd /tmp
  TARBALL="slurm-$${SLURM_VERSION}.tar.bz2"
  URL="https://download.schedmd.com/slurm/$${TARBALL}"
  wget -q "$${URL}" || curl -fsSL -o "$${TARBALL}" "$${URL}" || {
    echo "FATAL: failed to download $${URL}" >&2
    return 1
  }
  rm -rf "slurm-$${SLURM_VERSION}"
  tar -xjf "$${TARBALL}"
  cd "slurm-$${SLURM_VERSION}"
  # Prefer shared EFS prefix so all nodes can use the same build
  # --with-mysql_config must be the *directory* containing mysql_config (not the binary)
  MYSQLCFG_DIR=$(dirname "$(command -v mysql_config)")
  ./configure --prefix=/shared/software/slurm --sysconfdir=/etc/slurm \
    --with-munge=/usr --with-mysql_config="$${MYSQLCFG_DIR}" --disable-debug || {
    echo "FATAL: Slurm configure with MySQL failed" >&2
    return 1
  }
  make -j"$(nproc 2>/dev/null || echo 2)" || {
    echo "FATAL: Slurm make failed" >&2
    return 1
  }
  make install || {
    echo "FATAL: Slurm make install failed" >&2
    return 1
  }
  test -x /shared/software/slurm/sbin/slurmctld || {
    echo "FATAL: slurmctld binary missing after install" >&2
    return 1
  }
  test -x /shared/software/slurm/sbin/slurmdbd || {
    echo "FATAL: slurmdbd binary missing after install" >&2
    return 1
  }
  test -f /shared/software/slurm/lib/slurm/accounting_storage_mysql.so \
    -o -f /shared/software/slurm/lib64/slurm/accounting_storage_mysql.so || {
    echo "FATAL: accounting_storage_mysql.so not built" >&2
    return 1
  }
  # Point /opt/slurm at the MySQL-enabled build (replace empty dir only; prefer symlink)
  if [ -d /opt/slurm ] && [ ! -L /opt/slurm ]; then
    # AMI tree without mysql plugin — move aside and symlink EFS build
    mv /opt/slurm "/opt/slurm.ami-no-mysql.$$" 2>/dev/null || rm -rf /opt/slurm
  fi
  ln -sfn /shared/software/slurm /opt/slurm
  echo "Slurm built with MySQL and published to /shared/software/slurm"
  return 0
}
if ! install_slurm; then
  echo "FATAL: install_slurm failed — slurmctld will not start" >&2
  ls -la /opt/slurm /shared/software/slurm 2>/dev/null || true
fi

# Re-link only if needed (safe now — will not destroy AMI tree)
link_opt_slurm
echo 'export PATH=/opt/slurm/bin:/opt/slurm/sbin:$PATH' > /etc/profile.d/slurm.sh
chmod 644 /etc/profile.d/slurm.sh
export PATH=/opt/slurm/bin:/opt/slurm/sbin:$PATH
for b in sinfo squeue sbatch scancel scontrol srun sacct; do
  [ -x "/opt/slurm/bin/$b" ] && ln -sfn "/opt/slurm/bin/$b" "/usr/local/bin/$b"
done
for b in slurmctld slurmd; do
  [ -x "/opt/slurm/sbin/$b" ] && ln -sfn "/opt/slurm/sbin/$b" "/usr/local/sbin/$b"
done

# Identity: SlurmctldHost must match this host (Private Hosted Zone + local hosts)
CTRL_HOST="${var.project}-controller.${var.private_hosted_zone_name}"
CTRL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
hostnamectl set-hostname "$${CTRL_HOST}" 2>/dev/null || hostname "$${CTRL_HOST}" || true
# IPv4 first; avoid link-local-only resolution of controller name
sed -i "/$${CTRL_HOST}/d" /etc/hosts 2>/dev/null || true
echo "$${CTRL_IP}  $${CTRL_HOST} ${var.project}-controller" >> /etc/hosts
# Do NOT hard-code debug/std private IPs — they change on every rebuild.
# Debug publishes its IP to /shared/cluster/debug-1.ip and we scontrol update.
# Route53 private zone records are the long-term resolution path.
mkdir -p /shared/cluster
chown slurm:slurm /shared/cluster 2>/dev/null || true

mkdir -p /var/run/slurm /run/slurm
chown slurm:slurm /var/run/slurm /run/slurm

# Always start with accounting_storage/none so slurmctld never depends on a
# missing MySQL plugin. Upgrade to slurmdbd only after plugin + DBD are healthy.
cat > /etc/slurm/slurm.conf <<SLURMCONF
ClusterName=hpc-cluster
SlurmctldHost=$${CTRL_HOST}($${CTRL_IP})
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
AccountingStorageType=accounting_storage/none
JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=30
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_CPU
PartitionName=debug Priority=50 Default=YES MaxTime=24:00:00 State=UP Nodes=debug-1
PartitionName=std Priority=40 Default=NO MaxTime=7-00:00:00 State=UP Nodes=std-[1-3]
# No static NodeAddr — debug registers IP via EFS + scontrol. RealMemory for t3.micro-class.
NodeName=debug-1 CPUs=2 RealMemory=800 State=UNKNOWN
NodeName=std-[1-3] CPUs=2 RealMemory=800 State=CLOUD
SuspendTime=300
ReturnToService=1
SLURMCONF
chown -R slurm:slurm /etc/slurm /shared/slurm-state
chmod 644 /etc/slurm/slurm.conf
echo "none" > /shared/cluster/accounting_mode

# --- Optional slurmdbd → RDS (only if plugin exists AND enable_mariadb) ---
ENABLE_MARIADB="${var.enable_mariadb}"
MDB_HOST="${local.mariadb_host}"
MDB_PORT="${local.mariadb_port}"
MDB_USER="${var.mariadb_username}"
MDB_PASS='${var.mariadb_password}'
MDB_DB="${var.mariadb_db_name}"
ACCT_OK=0
if [ "$ENABLE_MARIADB" = "true" ] && [ -n "$MDB_HOST" ]; then
  if ! has_mysql_acct_plugin; then
    echo "WARN: accounting_storage_mysql.so missing — keeping AccountingStorageType=none"
    ls /opt/slurm/lib*/slurm/ 2>/dev/null | head -20 || true
  elif [ ! -x /opt/slurm/sbin/slurmdbd ]; then
    echo "WARN: slurmdbd binary missing — keeping AccountingStorageType=none"
  else
    mkdir -p /var/log/slurm /var/run/slurm
    chown slurm:slurm /var/log/slurm /var/run/slurm
    cat > /etc/slurm/slurmdbd.conf <<DBDEOF
AuthType=auth/munge
DbdHost=localhost
DbdPort=6819
SlurmUser=slurm
StorageType=accounting_storage/mysql
StorageHost=$${MDB_HOST}
StoragePort=$${MDB_PORT}
StorageUser=$${MDB_USER}
StoragePass=$${MDB_PASS}
StorageLoc=$${MDB_DB}
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/var/run/slurm/slurmdbd.pid
DBDEOF
    chown slurm:slurm /etc/slurm/slurmdbd.conf
    chmod 600 /etc/slurm/slurmdbd.conf

    cat >/usr/lib/systemd/system/slurmdbd.service <<'DBDSVC'
[Unit]
Description=Slurm DB daemon
After=network-online.target munge.service
Wants=network-online.target
Requires=munge.service
Before=slurmctld.service
[Service]
Type=simple
Environment=LD_LIBRARY_PATH=/opt/slurm/lib:/opt/slurm/lib64
ExecStart=/opt/slurm/sbin/slurmdbd -D
Restart=on-failure
RestartSec=5
User=slurm
Group=slurm
[Install]
WantedBy=multi-user.target
DBDSVC
    systemctl daemon-reload
    if systemctl is-active --quiet munge; then
      for _w in $(seq 1 30); do
        if command -v mysql >/dev/null 2>&1; then
          mysql -h "$MDB_HOST" -P "$MDB_PORT" -u "$MDB_USER" -p"$MDB_PASS" -e "SELECT 1" "$MDB_DB" 2>/dev/null && break
        else
          timeout 2 bash -c "echo >/dev/tcp/$${MDB_HOST}/$${MDB_PORT}" 2>/dev/null && break
        fi
        sleep 10
      done
      systemctl enable slurmdbd 2>/dev/null || true
      systemctl restart slurmdbd 2>/dev/null || true
      sleep 3
      if systemctl is-active --quiet slurmdbd; then
        # Promote conf only after DBD is actually up
        sed -i 's|^AccountingStorageType=.*|AccountingStorageType=accounting_storage/slurmdbd|' /etc/slurm/slurm.conf
        grep -q '^AccountingStorageHost=' /etc/slurm/slurm.conf \
          || echo 'AccountingStorageHost=localhost' >> /etc/slurm/slurm.conf
        sed -i 's|^AccountingStorageHost=.*|AccountingStorageHost=localhost|' /etc/slurm/slurm.conf
        grep -q '^AccountingStoragePort=' /etc/slurm/slurm.conf \
          || echo 'AccountingStoragePort=6819' >> /etc/slurm/slurm.conf
        sed -i 's|^AccountingStoragePort=.*|AccountingStoragePort=6819|' /etc/slurm/slurm.conf
        export PATH=/opt/slurm/bin:/opt/slurm/sbin:$PATH
        sacctmgr -i add cluster hpc-cluster 2>/dev/null || true
        sacctmgr -i add account root Description="root" 2>/dev/null || true
        sacctmgr -i add user root Account=root 2>/dev/null || true
        echo "slurmdbd" > /shared/cluster/accounting_mode
        ACCT_OK=1
        echo "Accounting enabled (slurmdbd + MariaDB)"
      else
        echo "WARN: slurmdbd failed to stay active — keeping AccountingStorageType=none" >&2
        journalctl -u slurmdbd -n 40 --no-pager || true
        systemctl disable slurmdbd 2>/dev/null || true
        systemctl stop slurmdbd 2>/dev/null || true
      fi
    fi
  fi
else
  echo "MariaDB accounting not requested or host empty (ENABLE_MARIADB=$ENABLE_MARIADB MDB_HOST=$MDB_HOST)"
fi
[ "$ACCT_OK" = "1" ] || echo "none" > /shared/cluster/accounting_mode

# seff: sacct-based Python wrapper (SchedMD Perl seff needs Slurmdb.pm / perlapi)
cat > /usr/local/bin/seff <<'SEFFEOF'
#!/usr/bin/env python3
"""Job efficiency from sacct (CPU/Mem). Requires accounting enabled."""
import sys, subprocess
if len(sys.argv) < 2:
    print("Usage: seff <jobid>", file=sys.stderr); sys.exit(1)
jid = sys.argv[1]
fmt = "JobID,JobName,State,Elapsed,TotalCPU,AllocCPUS,ReqMem,MaxRSS,AveRSS,NodeList"
out = subprocess.run(["sacct", "-j", jid, "-n", "-P", f"--format={fmt}"],
                     capture_output=True, text=True)
if out.returncode != 0 or not out.stdout.strip():
    print(out.stderr or "No accounting data (is slurmdbd/MariaDB configured?)", file=sys.stderr)
    sys.exit(1)
print(f"Job efficiency for {jid}:")
for line in out.stdout.strip().splitlines():
    print(" ", line.replace("|", "  "))
SEFFEOF
chmod 755 /usr/local/bin/seff
# Prefer working wrapper over broken Perl contrib seff on PATH
ln -sfn /usr/local/bin/seff /opt/slurm/bin/seff 2>/dev/null || cp -f /usr/local/bin/seff /opt/slurm/bin/seff

# AMI only ships cgroup/v1 plugin; force it so slurmd/slurmctld do not default to v2
cat > /etc/slurm/cgroup.conf <<'EOF'
CgroupPlugin=cgroup/v1
CgroupAutomount=yes
ConstrainCores=no
ConstrainRAMSpace=no
ConstrainDevices=no
EOF
chown slurm:slurm /etc/slurm/cgroup.conf
chmod 644 /etc/slurm/cgroup.conf

# systemd units
cat >/usr/lib/systemd/system/slurmctld.service <<'EOF'
[Unit]
Description=Slurm controller daemon
After=network-online.target munge.service
Wants=network-online.target
Requires=munge.service
[Service]
Type=simple
Environment=LD_LIBRARY_PATH=/opt/slurm/lib
ExecStart=/opt/slurm/sbin/slurmctld -D
Restart=on-failure
RestartSec=5
User=slurm
Group=slurm
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
if systemctl is-active --quiet munge && [ -x /opt/slurm/sbin/slurmctld ]; then
  systemctl enable slurmctld 2>/dev/null || true
  systemctl restart slurmctld 2>/dev/null || true
  sleep 2
  systemctl is-active slurmctld || journalctl -u slurmctld -n 30 --no-pager || true
  ss -lntp | grep 6817 || true
else
  echo "Skip slurmctld start (munge inactive or binary missing)"
  ls -la /opt/slurm/sbin/ 2>/dev/null || true
fi
# Symlink tools into default PATH for ssm-user / non-login shells
for b in sinfo squeue sbatch scancel scontrol srun; do
  [ -x "/opt/slurm/bin/$b" ] && ln -sfn "/opt/slurm/bin/$b" "/usr/local/bin/$b"
done

# Background: when debug publishes its IP on EFS, register NodeAddr with slurmctld
# (avoids hard-coded 10.0.100.96 that breaks after every instance replace)
cat > /usr/local/sbin/slurm-register-debug.sh <<'REGEOF'
#!/bin/bash
export PATH=/opt/slurm/bin:/opt/slurm/sbin:/usr/local/bin:$PATH
IP_FILE=/shared/cluster/debug-1.ip
for i in $(seq 1 60); do
  if [ -s "$IP_FILE" ] && systemctl is-active --quiet slurmctld; then
    DIP=$(tr -d '[:space:]' < "$IP_FILE")
    if echo "$DIP" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      sed -i '/debug-1/d' /etc/hosts 2>/dev/null || true
      echo "$DIP  debug-1.__PRIVATE_ZONE__ debug-1" >> /etc/hosts
      scontrol update NodeName=debug-1 NodeAddr="$DIP" 2>/dev/null && {
        echo "Registered debug-1 NodeAddr=$DIP"
        exit 0
      }
    fi
  fi
  sleep 10
done
echo "WARN: debug-1 IP registration timed out" >&2
exit 1
REGEOF
sed -i "s|__PRIVATE_ZONE__|${var.private_hosted_zone_name}|g" /usr/local/sbin/slurm-register-debug.sh
chmod 755 /usr/local/sbin/slurm-register-debug.sh
nohup /usr/local/sbin/slurm-register-debug.sh >> /var/log/slurm-register-debug.log 2>&1 &

echo "=== controller bootstrap done $(date -u) ==="
/opt/slurm/bin/sinfo -V 2>/dev/null || true
systemctl is-active slurmctld munge || true
USERDATA
}

# =============================================================================
# Munge key (Secrets Manager)
# =============================================================================

resource "random_id" "munge" {
  byte_length = 32
}

resource "aws_secretsmanager_secret" "munge_key" {
  name                    = "${var.project}-${var.env}-${var.session}-munge-key"
  recovery_window_in_days = 0
  kms_key_id              = try(var.kms_key_arns["secrets_manager"], null)

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-munge-key"
  })
}

resource "aws_secretsmanager_secret_version" "munge_key" {
  secret_id = aws_secretsmanager_secret.munge_key.id
  # random_id.b64_std is already base64 of 32 random bytes — store once, decode once on nodes
  secret_string = jsonencode({
    munge_key = random_id.munge.b64_std
  })
}

# =============================================================================
# IAM role for controller
# =============================================================================

resource "aws_iam_role" "controller" {
  name = "${var.project}-${var.env}-${var.session}-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-controller-role"
  })
}

resource "aws_iam_role_policy" "controller" {
  name = "${var.project}-${var.env}-${var.session}-controller-policy"
  role = aws_iam_role.controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.munge_key.arn
      },
      {
        # CMK-encrypted secrets require kms:Decrypt in addition to GetSecretValue
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = try(var.kms_key_arns["secrets_manager"], "*")
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:CreateTags",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:DescribeMountTargets"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "controller_ssm" {
  role       = aws_iam_role.controller.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "controller" {
  name = "${var.project}-${var.env}-${var.session}-controller-profile"
  role = aws_iam_role.controller.name
}

# =============================================================================
# Controller EC2 instance
# =============================================================================

resource "aws_instance" "controller" {
  ami                    = var.ami_id
  instance_type          = var.controller_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.security_group_ids["controller"]]
  iam_instance_profile   = aws_iam_instance_profile.controller.name
  # EC2 user-data limit is 16 KiB. Gzip keeps the bootstrap under the limit;
  # AL2023 cloud-init decompresses automatically.
  user_data_base64 = base64gzip(local.controller_user_data)

  root_block_device {
    volume_size           = var.controller_ebs_volume_size
    volume_type           = var.controller_ebs_volume_type
    iops                  = var.controller_ebs_volume_iops
    throughput            = var.controller_ebs_volume_throughput
    encrypted             = true
    kms_key_id            = try(var.kms_key_arns["ebs"], null)
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-${var.session}-controller"
    Role = "controller"
  })

  user_data_replace_on_change = true

  lifecycle {
    # Allow AMI updates from make ami-build / promote to roll instances
    create_before_destroy = true
  }

  # Wait for RDS so user_data gets a real endpoint (and DB accepts connections)
  depends_on = [
    aws_secretsmanager_secret_version.munge_key,
    aws_db_instance.mariadb,
  ]
}

resource "aws_route53_record" "controller" {
  zone_id = var.private_hosted_zone_id
  name    = "${var.project}-controller.${var.private_hosted_zone_name}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.controller.private_ip]
}

# =============================================================================
# MariaDB RDS Instance (for slurmdbd)
# =============================================================================

resource "aws_db_subnet_group" "mariadb" {
  count = var.enable_mariadb ? 1 : 0

  # Must match the existing AWS name for this session. Changing it makes
  # Terraform try to delete the old group while RDS still uses it
  # (InvalidDBSubnetGroupStateFault). Keep session in the name for live stacks.
  name       = "${var.project}-${var.env}-${var.session}-mariadb-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-mariadb-subnet-group"
    Session = var.session
  }
}

resource "aws_db_instance" "mariadb" {
  count = var.enable_mariadb ? 1 : 0

  identifier             = "${var.project}-${var.env}-${var.session}-mariadb"
  engine                 = "mariadb"
  engine_version         = "10.11"
  instance_class         = var.mariadb_instance_class
  allocated_storage      = var.mariadb_allocated_storage
  storage_type           = "gp2"
  db_name                = var.mariadb_db_name
  username               = var.mariadb_username
  password               = var.mariadb_password
  db_subnet_group_name   = aws_db_subnet_group.mariadb[0].name
  vpc_security_group_ids = [var.security_group_ids["controller"]]
  multi_az               = false
  publicly_accessible    = false
  backup_retention_period = 1
  storage_encrypted      = true
  kms_key_id             = try(var.kms_key_arns["secrets_manager"], null)
  skip_final_snapshot    = true

  tags = {
    Name    = "${var.project}-${var.env}-${var.session}-mariadb"
    Session = var.session
  }

  # Never attempt in-place subnet-group moves (AWS rejects same-VPC moves).
  lifecycle {
    ignore_changes = [db_subnet_group_name]
  }
}

# =============================================================================
# EFS CloudWatch Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "efs_burst_credits" {
  count = 1  # always; FileSystemId is set after storage apply via var

  alarm_name          = "${var.project}-${var.env}-${var.session}-controller-efs-burst"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 100000000000
  alarm_description   = "EFS burst credits low"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = var.efs_file_system_id
  }

  tags = merge(local.common_tags, {
    severity = "SEV-2"
    sli      = "storage_health"
    runbook  = "runbooks/connectivity-triage.md"
  })
}

resource "aws_cloudwatch_metric_alarm" "efs_storage_utilization" {
  count = 1  # always; FileSystemId is set after storage apply via var

  alarm_name          = "${var.project}-${var.env}-${var.session}-controller-efs-util"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StorageBytes"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 900000000000
  alarm_description   = "EFS storage high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = var.efs_file_system_id
    StorageClass = "Total"
  }

  tags = merge(local.common_tags, {
    severity = "SEV-3"
    sli      = "storage_health"
    runbook  = "runbooks/connectivity-triage.md"
  })
}
