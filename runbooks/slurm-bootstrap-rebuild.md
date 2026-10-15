# Slurm bootstrap — clean rebuild checklist (2026-10-12)

Lessons from the broken first deploy. Code in `terraform/controller`, `terraform/login`, and `terraform/image-builder/components/slurm_build.yaml` was updated to address these.

## Failures observed

| # | Symptom | Root cause |
|---|---------|------------|
| 1 | No `/opt/slurm` binaries | Image Builder AMI not used / not built; controller fallback build never produced binaries |
| 2 | `gcc` / `make` missing | `dnf install … curl …` failed on AL2023 (`curl` vs `curl-minimal`); whole package transaction skipped |
| 3 | `install_slurm` claimed success | `set +e` + no check for `sbin/slurmctld` after `make install` |
| 4 | `203/EXEC` on slurmctld/slurmd | `/opt/slurm` was a **directory**; `ln -sfn target /opt/slurm` created `/opt/slurm/slurm` instead of replacing the path |
| 5 | `not a valid controller` | OS hostname ≠ `SlurmctldHost` |
| 6 | Pidfile permission denied | Unit runs as `slurm`; `/var/run/slurmctld.pid` not writable |
| 7 | `Unable to create NodeAddr list from std-[1-3].hpc.internal` | Cloud node names have no DNS records at controller start |
| 8 | `libhwloc.so.15: cannot open shared object file` | Slurm linked against hwloc on controller; debug node lacked `hwloc-libs` |
| 9 | Login `connect failure` | Controller crash-looping (above) and/or name resolution quirks |

## Code fixes applied

1. **Packages (all nodes):** do not install full `curl`; install `hwloc` / `hwloc-libs` on login + debug; ensure `gcc`/`make` on controller.
2. **`/opt/slurm`:** never `mkdir /opt/slurm` before symlink; `rm -rf` empty dir then `ln -sfn /shared/software/slurm /opt/slurm`.
3. **`install_slurm`:** fail if configure/make/install fail or `sbin/slurmctld` / `sbin/slurmd` missing.
4. **Controller identity:** `hostnamectl` to `SlurmctldHost`; `/etc/hosts` IPv4; `SlurmctldHost=name(ip)`; pid files under `/var/run/slurm/`.
5. **NodeAddr:** numeric IPs for debug + std range so controller can start without Route53 for cloud nodes.
6. **Debug:** set hostname `debug-1.…`, install hwloc, validate `slurmd` binary before enable.
7. **Image Builder `slurm_build.yaml`:** no curl package; require gcc; assert daemon binaries after install; install hwloc runtime.

## Rebuild procedure (tomorrow)

```bash
# 1) Prefer a real HPC AMI (avoids 10–20 min compile on controller)
cd hpc-testbed
make ami-build
# wait for pipeline; confirm SSM param points at new AMI
aws ssm get-parameter --name /hpc-testbed/ami/compute/current --query Parameter.Value --output text

# 2) Destroy / apply as you normally do for a clean session
#    Ensure user-data changes are in the plan (controller + login modules)

# 3) After apply, verify without SSM spelunking:
# Controller
systemctl is-active munge slurmctld
ss -lntp | grep 6817
test -x /opt/slurm/sbin/slurmctld && /opt/slurm/sbin/slurmctld -V
# Login
scontrol ping
sinfo
# Debug
systemctl is-active slurmd
scontrol show node debug-1
srun -p debug -N1 -n1 hostname
```

## If controller still builds from source

- Instance type should allow ~2 vCPU and enough memory for `make` (avoid tiny types).
- First boot may take 15–25 minutes before `/shared/software/slurm` appears; login/debug wait loops are 60 × 15s.

## Residual / follow-ups

- **std-[1-3]** nodes remain `State=CLOUD` without static NodeAddr; power/resume scripts must `scontrol update` real addresses when instances launch (or rely on Route53 names).
- Prefer Image Builder AMI so nodes do not depend on the EFS compile path: **`make ami-build` then `make up`**.
- Consider sharing one `slurm.conf` from EFS (`/shared/cluster/slurm.conf`) to avoid drift between controller/login/debug.

## Fixes applied 2026-10-13 (post second deploy)

| # | Symptom | Root cause | Fix |
|---|---------|------------|-----|
| 10 | Controller: "Using Slurm from AMI" then `slurmctld` missing | `link_opt_slurm` always `rm -rf /opt/slurm` when it is a real dir, even if AMI binaries are present | Preserve working AMI tree; only replace when binaries are missing |
| 11 | Debug: `cannot find cgroup plugin for cgroup/v2` | AMI only ships `cgroup_v1.so`; no `cgroup.conf` written | Write `CgroupPlugin=cgroup/v1` on controller + debug (+ login) |
| 12 | Debug IP ≠ controller NodeAddr (e.g. .89 vs .96) | Static placeholder | Keep placeholder for boot; debug uses real `DEBUG_IP` in its conf; use `scontrol update` / stable ENI long-term |
| 13 | Noisy `/home` EFS mount failures | EFS had no top-level `/home` dir | Controller creates `/shared/home` (= EFS:/home); login/debug treat /home mount as best-effort |
| 14 | Topology warning (Sockets/Threads) | Over-specified NodeName vs real hardware | Use `CPUs=2` only |

## Fixes applied 2026-10-14 (dynamic NodeAddr + SG + hostname)

| # | Symptom | Root cause | Fix |
|---|---------|------------|-----|
| 15 | Connectivity fails after `make ami-build` + instance replace | Hard-coded `NodeAddr=10.0.100.96` / `/etc/hosts` on controller + login | No static NodeAddr; debug writes `/shared/cluster/debug-1.ip`; controller registers via `scontrol update`; debug also pushes `scontrol update` |
| 16 | Login hostname unset | Login user-data never called `hostnamectl` | Set `login.<zone>` + `/etc/hosts` entry at boot |
| 17 | Controller `/etc/hosts` stale for debug/std | Static 10.0.100.96–103 placeholders | Removed; debug IP synced when registration runs |
| 18 | Possible high-port drops debug↔controller/login | SG only allowed 6817/6818 | Ephemeral TCP 1024–65535 from VPC on controller, login, and debug SGs; debug also attaches network compute SG |
| 19 | AMI-after-instances skew | Instances boot before new AMI | Documented order: `make ami-build` then `make up` |
