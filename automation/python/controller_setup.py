#!/usr/bin/env python3
"""
Slurm Controller Setup Script
================================

This script provides utilities for setting up and verifying the Slurm controller node.
It handles configuration file generation, service management, and health checks.

Usage:
    python controller_setup.py [command] [options]

Commands:
    generate-config     Generate Slurm configuration files from templates
    verify-connection   Verify connectivity to MariaDB and other services
    check-health        Check health of Slurm services
    generate-key        Generate Munge key and store in Secrets Manager
    deploy              Deploy controller configuration
    validate            Validate Slurm configuration
"""

import argparse
import json
import logging
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

import boto3

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("controller_setup")

# =============================================================================
# Configuration Constants
# =============================================================================

DEFAULT_SLURM_VERSION = "23.02.4"
DEFAULT_SLURM_STATE_DIR = "/var/spool/slurmctld"
DEFAULT_MARIADB_DB_NAME = "slurm_acct_db"
DEFAULT_MARIADB_USERNAME = "slurm"
DEFAULT_MARIADB_PORT = 3306
DEFAULT_MUNGE_KEY_LENGTH = 64

# =============================================================================
# Configuration Classes
# =============================================================================


class SlurmConfig:
    """Slurm configuration data."""

    def __init__(
        self,
        controller_hostname: str,
        controller_ip: str,
        debug_hostname: str,
        debug_ip: str,
        std_node_prefix: str,
        std_node_count: int,
        slurm_version: str = DEFAULT_SLURM_VERSION,
        slurm_state_dir: str = DEFAULT_SLURM_STATE_DIR,
        mariadb_host: str = "localhost",
        mariadb_port: int = DEFAULT_MARIADB_PORT,
        mariadb_db_name: str = DEFAULT_MARIADB_DB_NAME,
        mariadb_username: str = DEFAULT_MARIADB_USERNAME,
        munge_key_secret_arn: Optional[str] = None,
    ):
        self.controller_hostname = controller_hostname
        self.controller_ip = controller_ip
        self.debug_hostname = debug_hostname
        self.debug_ip = debug_ip
        self.std_node_prefix = std_node_prefix
        self.std_node_count = std_node_count
        self.slurm_version = slurm_version
        self.slurm_state_dir = slurm_state_dir
        self.mariadb_host = mariadb_host
        self.mariadb_port = mariadb_port
        self.mariadb_db_name = mariadb_db_name
        self.mariadb_username = mariadb_username
        self.munge_key_secret_arn = munge_key_secret_arn


class TemplateRenderer:
    """Render Slurm configuration templates with variables."""

    def __init__(self, config: SlurmConfig):
        self.config = config

    def render_slurm_conf(self) -> str:
        """Render slurm.conf template."""
        nodes = self._generate_node_definitions()
        partitions = self._generate_partition_definitions()

        return f"""# Slurm controller configuration file
# Generated at {datetime.now().isoformat()}

# =============================================================================
# Slurm Controller Configuration
# =============================================================================

ClusterName=hpc-cluster
SlurmctldHost={self.config.controller_hostname}({self.config.controller_ip})
SlurmUser=slurm
SlurmctldPidFile=/var/spool/slurmctld/slurmctld.pid
SlurmctldLogDir=/var/log/slurmctld
SlurmctldPort=6817
SlurmdPidFile=/var/spool/slurmd/slurmd.pid
SlurmdLogDir=/var/log/slurmd
SlurmdPort=6818
SlurmSpoolDir=/var/spool/slurm
SlurmStateDir={self.config.slurm_state_dir}
SlurmctldSyslogDebug=info
SlurmctldDebug=info

# =============================================================================
# Authentication Configuration
# =============================================================================

AuthType=auth/munge
AuthArgs=ConfigureMungeKey=yes
CredType=cred/munge
KeyLength=64
RotatingTime=7d
CycleLength=30s

# =============================================================================
# Partition Definitions
# =============================================================================

{partitions}

# =============================================================================
# Node Definitions
# =============================================================================

{nodes}

# =============================================================================
# Power Management Settings
# =============================================================================

ResumeProgram=/opt/hpc/scripts/resume_nodes.sh
SuspendProgram=/opt/hpc/scripts/suspend_nodes.sh
SuspendTime=300
SuspendTimeout=90
ResumeTimeout=300
ResumeRate=100
SuspendRate=100
PowerSave=NO
PowerProgram=/opt/hpc/scripts/power_save.sh

# =============================================================================
# Accounting Configuration
# =============================================================================

AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost={self.config.controller_hostname}
AccountingStoragePort=6819
AccountingStorageUser=slurm
AccountingStoreJobComment=YES
AccountingStoreFlags=job_script

# =============================================================================
# Job Configuration
# =============================================================================

SchedulerType=sched/backfill
SchedulerPort=7030
SelectType=select/linear
DefMemPerCPU=1024
MaxMemPerCPU=4096
MinMemPerNode=0

# =============================================================================
# Logging Configuration
# =============================================================================

SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurmctld/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurmd/slurmd.log

# =============================================================================
# Security Configuration
# =============================================================================

JobSubmitPlugins=lua

# =============================================================================
# GRES Configuration
# =============================================================================

GresTypes=gpu
"""

    def render_slurmdbd_conf(self) -> str:
        """Render slurmdbd.conf template."""
        return f"""# Slurm DB Daemon configuration file
# Generated at {datetime.now().isoformat()}

# =============================================================================
# Database Connection Configuration
# =============================================================================

DBDHost={self.config.controller_hostname}
DbdPort=6819
DbdAuth=auth/mysql
DbdParams={self.config.mariadb_host}:{self.config.mariadb_port},{self.config.mariadb_db_name},{self.config.mariadb_username},{{MARIADB_PASSWORD}}
AccountingStorageType=accounting_storage/mysql

# =============================================================================
# Slurmdbd Configuration
# =============================================================================

SlurmdbdUser=slurm
SlurmdbdPidFile=/var/run/slurmdbd.pid
SlurmdbdLogDir=/var/log/slurmdbd
SlurmdbdDebug=info
SlurmdbdLogFile=/var/log/slurmdbd/slurmdbd.log

# =============================================================================
# Message Logging
# =============================================================================

# Log level
SlurmdbdLogFile=/var/log/slurmdbd/slurmdbd.log

# =============================================================================
# Connection Retries
# =============================================================================

DbdRetainSeconds=300
DbdMessageSize=10485760
"""

    def render_cgroup_conf(self) -> str:
        """Render cgroup.conf template."""
        return f"""# Slurm cgroup configuration file
# Generated at {datetime.now().isoformat()}

# =============================================================================
# Cgroup Configuration
# =============================================================================

CgroupAutomount=yes
CgroupMountpoint=/sys/fs/cgroup
CgroupPlugin=controller/cgroup

# =============================================================================
# Task Plugin
# =============================================================================

TaskPlugin=task/affinity

# =============================================================================
# CPU Affinity
# =============================================================================

TaskAffinity=yes
CpuAffinityPlugin=affinity

# =============================================================================
# Memory Management
# =============================================================================

MemoryAffinityPlugin=affinity
TaskPlugin=task/affinity

# =============================================================================
# Slurmctld Parameters
# =============================================================================

SlurmctldParameters=enable_debug,profile_gres

# =============================================================================
# Prolog/Epilog Configuration
# =============================================================================

Prolog=/opt/hpc/scripts/cgroup_prolog.sh
Epilog=/opt/hpc/scripts/cgroup_epilog.sh
TaskProlog=/opt/hpc/scripts/cgroup_task_prolog.sh
TaskEpilog=/opt/hpc/scripts/cgroup_task_epilog.sh

# =============================================================================
# Allowed System Resources
# =============================================================================

AllowSpecResourcesUser=root,slurm

# =============================================================================
# Cgroup Automated Memory Management
# =============================================================================

CgroupAutomount=yes
CgroupPeriod=100000
CgroupVerbose=0
CgroupWrapTask=yes
"""

    def _generate_partition_definitions(self) -> str:
        """Generate partition definitions."""
        debug_partition = f"""PartitionName=debug Priority=50 Default=YES MaxTime=24:00:00 State=UP
    Nodes={self.config.debug_hostname}({self.config.debug_ip}) State=UNKNOWN"""

        std_partition = f"""PartitionName=std Priority=40 Default=NO MaxTime=7-00:00:00 State=UP
    Nodes={self.config.std_node_prefix}[1-{self.config.std_node_count}] State=UNKNOWN"""

        return f"{debug_partition}\n\n{std_partition}"

    def _generate_node_definitions(self) -> str:
        """Generate node definitions."""
        debug_node = f"""NodeName={self.config.debug_hostname} NodeAddr={self.config.debug_ip} CPUs=2 State=UNKNOWN"""

        std_nodes = "\n".join(
            f"""NodeName={self.config.std_node_prefix}{i} NodeAddr={self.config.std_node_prefix}{i}.hpc.internal CPUs=2 State=UNKNOWN"""
            for i in range(1, self.config.std_node_count + 1)
        )

        return f"{debug_node}\n\n{std_nodes}"


class SlurmControllerSetup:
    """Main controller setup class."""

    def __init__(self, config: SlurmConfig, config_dir: str = "config/slurm"):
        self.config = config
        self.config_dir = Path(config_dir)
        self.renderer = TemplateRenderer(config)

    def generate_config_files(self, output_dir: str = "/etc/slurm") -> None:
        """Generate and write Slurm configuration files."""
        output_path = Path(output_dir)

        # Create output directory if it doesn't exist
        output_path.mkdir(parents=True, exist_ok=True)

        # Generate and write configuration files
        slurm_conf = self.renderer.render_slurm_conf()
        slurmdbd_conf = self.renderer.render_slurmdbd_conf()
        cgroup_conf = self.renderer.render_cgroup_conf()

        (output_path / "slurm.conf").write_text(slurm_conf)
        (output_path / "slurmdbd.conf").write_text(slurmdbd_conf)
        (output_path / "cgroup.conf").write_text(cgroup_conf)

        logger.info(f"Generated Slurm configuration files in {output_dir}")

    def verify_mariadb_connection(self) -> bool:
        """Verify connectivity to MariaDB."""
        try:
            result = subprocess.run(
                [
                    "mysql",
                    "-h",
                    self.config.mariadb_host,
                    "-P",
                    str(self.config.mariadb_port),
                    "-u",
                    self.config.mariadb_username,
                    "-p",
                    "-e",
                    "SELECT 1",
                ],
                capture_output=True,
                text=True,
                timeout=30,
            )

            if result.returncode == 0:
                logger.info(f"Successfully connected to MariaDB at {self.config.mariadb_host}")
                return True
            else:
                logger.error(f"Failed to connect to MariaDB: {result.stderr}")
                return False
        except FileNotFoundError:
            logger.error("MySQL client not found. Install with: yum install -y mariadb")
            return False
        except subprocess.TimeoutExpired:
            logger.error("Connection to MariaDB timed out")
            return False

    def check_slurm_services(self) -> dict:
        """Check status of Slurm services."""
        services = ["slurmctld", "slurmd", "slurmdbd"]
        status = {}

        for service in services:
            try:
                result = subprocess.run(
                    ["systemctl", "is-active", service],
                    capture_output=True,
                    text=True,
                )
                status[service] = result.stdout.strip()
            except FileNotFoundError:
                status[service] = "unknown"

        return status

    def generate_munge_key(self) -> str:
        """Generate a new Munge key."""
        import secrets

        # Generate a 64-byte base64-encoded key
        key = secrets.token_urlsafe(64)
        return key

    def store_munge_key(self, key: str) -> bool:
        """Store Munge key in AWS Secrets Manager."""
        if not self.config.munge_key_secret_arn:
            logger.error("Munge key secret ARN not configured")
            return False

        try:
            session = boto3.Session()
            secrets_manager = session.client("secretsmanager")

            secret_value = json.dumps({"munge_key": key})

            # Update the secret value
            secrets_manager.put_secret_value(
                SecretId=self.config.munge_key_secret_arn,
                SecretString=secret_value,
            )

            logger.info("Successfully stored Munge key in Secrets Manager")
            return True
        except Exception as e:
            logger.error(f"Failed to store Munge key: {e}")
            return False

    def validate_slurm_config(self) -> bool:
        """Validate Slurm configuration files."""
        try:
            # Check if required files exist
            required_files = ["slurm.conf", "slurmdbd.conf", "cgroup.conf"]
            for filename in required_files:
                filepath = self.config_dir / filename
                if not filepath.exists():
                    logger.error(f"Required configuration file not found: {filepath}")
                    return False

            # Validate slurm.conf syntax
            result = subprocess.run(
                ["scontrol", "show", "config"],
                capture_output=True,
                text=True,
                timeout=60,
            )

            if result.returncode == 0:
                logger.info("Slurm configuration is valid")
                return True
            else:
                logger.error(f"Slurm configuration validation failed: {result.stderr}")
                return False
        except FileNotFoundError:
            logger.error("scontrol not found. Slurm must be installed.")
            return False
        except subprocess.TimeoutExpired:
            logger.error("Configuration validation timed out")
            return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Slurm Controller Setup")
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # Generate config command
    generate_parser = subparsers.add_parser("generate-config", help="Generate Slurm configuration files")
    generate_parser.add_argument("--controller-hostname", required=True, help="Controller hostname")
    generate_parser.add_argument("--controller-ip", required=True, help="Controller IP address")
    generate_parser.add_argument("--debug-hostname", required=True, help="Debug node hostname")
    generate_parser.add_argument("--debug-ip", required=True, help="Debug node IP address")
    generate_parser.add_argument("--std-node-prefix", default="std", help="Standard node name prefix")
    generate_parser.add_argument("--std-node-count", type=int, default=3, help="Number of standard nodes")
    generate_parser.add_argument("--output-dir", default="/etc/slurm", help="Output directory for config files")

    # Verify connection command
    verify_parser = subparsers.add_parser("verify-connection", help="Verify connectivity to services")
    verify_parser.add_argument("--mariadb-host", default="localhost", help="MariaDB hostname")

    # Check health command
    health_parser = subparsers.add_parser("check-health", help="Check health of Slurm services")

    # Generate key command
    key_parser = subparsers.add_parser("generate-key", help="Generate Munge key")
    key_parser.add_argument("--secret-arn", help="Secrets Manager ARN for Munge key")

    # Validate command
    validate_parser = subparsers.add_parser("validate", help="Validate Slurm configuration")

    # Deploy command
    deploy_parser = subparsers.add_parser("deploy", help="Deploy controller configuration")
    deploy_parser.add_argument("--controller-hostname", required=True, help="Controller hostname")
    deploy_parser.add_argument("--controller-ip", required=True, help="Controller IP address")
    deploy_parser.add_argument("--debug-hostname", required=True, help="Debug node hostname")
    deploy_parser.add_argument("--debug-ip", required=True, help="Debug node IP address")
    deploy_parser.add_argument("--std-node-prefix", default="std", help="Standard node name prefix")
    deploy_parser.add_argument("--std-node-count", type=int, default=3, help="Number of standard nodes")
    deploy_parser.add_argument("--output-dir", default="/etc/slurm", help="Output directory for config files")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == "generate-config":
        config = SlurmConfig(
            controller_hostname=args.controller_hostname,
            controller_ip=args.controller_ip,
            debug_hostname=args.debug_hostname,
            debug_ip=args.debug_ip,
            std_node_prefix=args.std_node_prefix,
            std_node_count=args.std_node_count,
        )
        setup = SlurmControllerSetup(config)
        setup.generate_config_files(args.output_dir)

    elif args.command == "verify-connection":
        config = SlurmConfig(mariadb_host=args.mariadb_host)
        setup = SlurmControllerSetup(config)
        success = setup.verify_mariadb_connection()
        sys.exit(0 if success else 1)

    elif args.command == "check-health":
        setup = SlurmControllerSetup(SlurmConfig(""))
        status = setup.check_slurm_services()
        for service, state in status.items():
            print(f"{service}: {state}")

    elif args.command == "generate-key":
        setup = SlurmControllerSetup(SlurmConfig(""))
        key = setup.generate_munge_key()
        print(key)
        if args.secret_arn:
            setup.store_munge_key(key)

    elif args.command == "validate":
        setup = SlurmControllerSetup(SlurmConfig(""))
        success = setup.validate_slurm_config()
        sys.exit(0 if success else 1)

    elif args.command == "deploy":
        config = SlurmConfig(
            controller_hostname=args.controller_hostname,
            controller_ip=args.controller_ip,
            debug_hostname=args.debug_hostname,
            debug_ip=args.debug_ip,
            std_node_prefix=args.std_node_prefix,
            std_node_count=args.std_node_count,
        )
        setup = SlurmControllerSetup(config)
        setup.generate_config_files(args.output_dir)

        # Validate configuration
        if not setup.validate_slurm_config():
            logger.error("Configuration validation failed")
            sys.exit(1)

        logger.info("Controller deployment successful")


if __name__ == "__main__":
    main()
