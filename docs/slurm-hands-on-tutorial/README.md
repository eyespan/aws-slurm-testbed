# Slurm Hands-on Tutorial

A practical learning lab based on SchedMD's official [Slurm command summary PDF](https://slurm.schedmd.com/pdfs/summary.pdf).

## Important: run this on a Slurm login node

These exercises require an existing Slurm cluster and the Slurm client commands (`sbatch`, `srun`, `squeue`, etc.). They are not expected to run on a normal laptop or workstation without Slurm configured. Use your organisation's login node, follow its workload policy, and never run compute workloads on a login node unless your administrator explicitly permits it.

The lab is designed to use small CPU jobs. It does not install software, modify cluster configuration, create accounts, or require administrator privileges. Some commands in the reference section are administrator-only or require optional Slurm accounting configuration.

## Quick start

1. Copy/extract this directory onto a Slurm login node.
2. Enter the extracted directory.
3. Run:

   ```bash
   chmod +x scripts/*.sh
   ./scripts/00_preflight.sh
   ```

4. If preflight succeeds, submit the first job:

   ```bash
   ./scripts/01_submit_hello.sh
   ```

5. Check the job:

   ```bash
   squeue -u "$USER"
   ```

   Once it has finished, inspect the files under `output/` and use:

   ```bash
   sacct -j JOB_ID --format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,MaxRSS
   ```

   Replace `JOB_ID` with the numeric ID printed by `sbatch`.

`sbatch` normally returns immediately after accepting the job; that means submitted, not necessarily started or completed.

## Lab map

| Lesson | Script / file | What you practise |
|---|---|---|
| 0 | `scripts/00_preflight.sh` | Check client commands, cluster and partitions |
| 1 | `scripts/01_submit_hello.sh`, `jobs/hello.sbatch` | `sbatch`, directives, logs, exit status |
| 2 | `scripts/02_srun_examples.sh` | `srun`, task labels, CPU requests |
| 3 | `scripts/03_job_array.sh`, `jobs/array.sbatch` | Array indexes and per-task output |
| 4 | `scripts/04_dependency_demo.sh` | Job dependencies (`afterok`) |
| 5 | `scripts/05_interactive_allocation.sh` | `salloc` followed by `srun` |
| 6 | `scripts/06_monitor_jobs.sh` | `squeue`, `scontrol`, `scancel` safely |
| 7 | `scripts/07_accounting.sh` | `sacct`, `sstat`, `sreport`, `sprio`, `sshare` |
| 8 | `scripts/08_cluster_inspection.sh` | `sinfo`, read-only `scontrol` |
| 9 | `scripts/09_environment.sh` | Slurm environment variables |
| 10 | `scripts/10_cancel_demo.sh` | Submit a long-running demo and cancel only that job |
| Reference | Below | All commands named in the cheat sheet, including optional/admin tools |

Output files are written into `output/`. The scripts create that directory when needed.

## Core concepts

- **Cluster:** the Slurm-managed compute environment.
- **Node:** a machine in the cluster.
- **Partition:** a configured queue of nodes with policy and limits.
- **Job:** a scheduled unit of work, often submitted with `sbatch`.
- **Job step:** work launched within a job allocation, commonly with `srun`.
- **Task:** a process launched by Slurm. `--ntasks`/`-n` controls task count.
- **CPU per task:** `--cpus-per-task` controls CPU allocation for each task.
- **Memory:** `--mem` is typically memory per node; cluster configuration can affect details.
- **Wall time:** `--time` is the maximum elapsed time requested.
- **Allocation:** resources granted to a job for its execution.
- **Job ID:** identifier returned by `sbatch`; use it to monitor, inspect or cancel the job.

## Lesson 0 — preflight

Run `./scripts/00_preflight.sh`. Review:
- `command -v sbatch` confirms the client is available.
- `sinfo` shows partitions and node states.
- `scontrol show config` may show configuration details depending on site policy.
- A partition can be listed but unavailable to your account; follow local documentation.

If a command is missing or reports that it cannot contact the controller, stop and contact the cluster administrator rather than installing a local Slurm package.

## Lesson 1 — submit a batch job

Run `./scripts/01_submit_hello.sh`. Read `jobs/hello.sbatch`.

Important directives:
- `#SBATCH --job-name=...`: human-readable job name.
- `#SBATCH --output=...`: standard output path.
- `#SBATCH --error=...`: standard error path.
- `#SBATCH --time=...`: wall-time limit.
- `#SBATCH --ntasks=1`: one task.
- `#SBATCH --cpus-per-task=1`: one CPU per task.
- `#SBATCH --mem=128M`: small memory request (adjust if your site enforces a larger minimum).

`#SBATCH` lines must appear before the first non-comment, non-whitespace shell command. Shell variables inside a `#SBATCH` directive are not expanded by the shell. This example uses a fixed relative output path after setting the working directory.

Observe the job at different times:
```bash
squeue -u "$USER"
squeue -j JOB_ID
scontrol show job JOB_ID
sacct -j JOB_ID --format=JobID,JobName,State,ExitCode,Elapsed
```

A very short job may finish before you can see it in `squeue`; `sacct` may still show it if accounting is enabled.

## Lesson 2 — run a task with srun

Run `./scripts/02_srun_examples.sh`. This script uses a short, single-node workload:
```bash
srun --ntasks=2 --cpus-per-task=1 --label hostname
```
The scheduler may reject the request if the default partition or account requires additional options. The `--label` option prefixes output with task IDs. `srun` can create an allocation when run outside a job, or launch a job step inside an existing allocation.

Compare:
- `srun hostname` — one task by default.
- `srun --ntasks=2 --label hostname` — two tasks, subject to cluster policy.
- `sbatch job.sbatch` — submit a script for later scheduling.
- `salloc ...` — request an interactive allocation, then launch steps using `srun`.

## Lesson 3 — job arrays

Run `./scripts/03_job_array.sh`. It submits indexes 1 through 5. Each array task receives `SLURM_ARRAY_TASK_ID`. Output and error filenames include `%A` (array job ID) and `%a` (array index).

Arrays are useful for parameter sweeps and independent data items. Do not create very large arrays without checking site policy and array limits.

## Lesson 4 — dependencies

Run `./scripts/04_dependency_demo.sh`. It submits a first job and then a second job with `--dependency=afterok:<jobid>`. The second job starts only if the first job completes successfully. The script prints both IDs. If the first job fails, the dependent job will not run successfully and may remain pending until Slurm marks the dependency unsatisfied.

Related dependency types include `after`, `afterany`, `afterok`, `afternotok`, and `singleton`; confirm exact semantics in `man sbatch` for your Slurm version.

## Lesson 5 — interactive allocation

Run `./scripts/05_interactive_allocation.sh` in an interactive terminal. It requests one task, one CPU, 512 MB memory and 10 minutes, then starts a shell inside the allocation. Inside that shell, run:
```bash
echo "$SLURM_JOB_ID"
srun hostname
srun --ntasks=2 --label hostname
exit
```
If the cluster requires an explicit partition/account, add the appropriate options to the script. Do not request more resources than the exercise needs.

## Lesson 6 — monitoring and cancellation

Run `./scripts/06_monitor_jobs.sh` to see common read-only views. It does not cancel jobs.

Useful commands:
```bash
squeue -u "$USER"
squeue --name=slurm-tutorial-hello
squeue --states=RUNNING,PENDING
scontrol show job JOB_ID
scancel JOB_ID
```
Only cancel jobs you own and intend to stop. `scancel` can terminate active work and may lose its results.

Run `./scripts/10_cancel_demo.sh` to submit a deliberately long-running, low-resource job. It prints the ID. Inspect it with `squeue -j JOB_ID`, then cancel only that exact ID with `scancel JOB_ID`. Verify its final state with `sacct -j JOB_ID`.

## Lesson 7 — accounting, usage and priority

Run `./scripts/07_accounting.sh`. Several commands depend on site configuration:
- `sacct`: completed/running job accounting; commonly available when accounting is enabled.
- `sstat`: live usage for a running job step; a short job may finish before it can return data.
- `sreport`: cluster/user utilisation reports; requires Slurm accounting data and appropriate permissions.
- `sprio`: priority components; useful where the configured priority plugin exposes them.
- `sshare`: fair-share information; meaningful when the cluster uses the relevant multifactor priority/fair-share configuration.

A “not configured”, “no data”, or permission error is a site capability issue, not necessarily a mistake in your command.

## Lesson 8 — cluster inspection

Run `./scripts/08_cluster_inspection.sh`. It uses read-only queries:
```bash
sinfo
sinfo --Node
sinfo --long
scontrol show partition
scontrol show nodes
scontrol show job JOB_ID
```
`scontrol` can also change cluster state. This tutorial intentionally avoids `update`, `reconfigure`, `create`, `delete`, `drain`, `resume`, and other state-changing/admin operations.

## Lesson 9 — Slurm environment variables

Run `./scripts/09_environment.sh`. Variables may include:
- `SLURM_JOB_ID`, `SLURM_JOB_NAME`
- `SLURM_JOB_PARTITION`, `SLURM_JOB_NODELIST`, `SLURM_JOB_NUM_NODES`
- `SLURM_CPUS_PER_TASK`
- `SLURM_PROCID`, `SLURM_STEP_ID`, `SLURM_STEP_NUM_TASKS`
- `SLURM_ARRAY_JOB_ID`, `SLURM_ARRAY_TASK_ID`
- `SLURM_RESTART_COUNT`, `SLURM_CLUSTER_NAME`, `SLURM_JOB_ACCOUNT`

Some variables exist only in a particular job, step, or array context. Outside Slurm, they may be unset.

## Cheat-sheet command reference

### Job submission and execution
- `sbatch`: submit a batch script.
- `srun`: create an allocation if needed and run a command, or launch a step in an existing allocation.
- `salloc`: obtain an allocation, often for interactive work.
- `scancel`: cancel jobs/steps or send a signal.
- `squeue`: inspect queued/running jobs.
- `sinfo`: inspect partitions and node states.
- `scontrol`: inspect or administer Slurm state/configuration. This tutorial uses read-only forms only.
- `sview`: optional graphical interface; availability depends on how Slurm was built and your environment.

### Accounting and priority (optional/site-dependent)
- `sacct`: job accounting.
- `sacctmgr`: manage/query accounting entities (accounts, associations, clusters, QOS). Most mutations are administrator/account-manager operations. Use `sacctmgr show ...` only unless you have explicit authorisation.
- `sreport`: utilisation and accounting reports.
- `sprio`: job priority breakdown.
- `sshare`: fair-share usage.
- `sstat`: statistics for running jobs/steps.

### Other commands shown in the official command summary
- `sbcast`: copy a file from a submit host to local storage on allocated nodes. Needs an allocation and a suitable node-local path; see `man sbcast`. Shared filesystems may make it unnecessary.
- `sattach`: attach to I/O/signals for an existing running job step. It is not a general way to attach to any process; see `man sattach`.
- `strigger`: configure/query event triggers. Availability and permissions depend on cluster configuration; avoid setting triggers without understanding their lifecycle.
- `sdiag`: controller scheduling diagnostic statistics; mainly useful to administrators and may be restricted.
- `scrontab`: Slurm-managed scheduled jobs; availability depends on installation/configuration.
- `sh5util`: HDF5 profiling utility; optional and not present on every installation.
- `slurmrestd`: Slurm REST API daemon; typically administrator-managed, not a command to launch casually as a normal user.
- `slurmctld`: central controller daemon, normally administrator-managed.
- `slurmd`: node daemon, normally administrator-managed.
- `slurmdbd`: accounting database daemon, normally administrator-managed.

### Common resource options from the cheat sheet
- `--nodes` / `-N`: node count or range.
- `--ntasks` / `-n`: number of tasks.
- `--nodelist`: specific node names; usually avoid pinning to nodes unless required by site policy.
- `--cpus-per-task`: CPUs per task.
- `--mem`: memory per node.
- `--mem-per-cpu`: memory per allocated CPU.
- `--gres`: generic resources, often GPUs; resource names are cluster-specific.
- `--partition`: partition/queue.
- `--qos`: quality of service; site-defined.
- `--account`: accounting account; site-defined.
- `--constraint`: node features; site-defined.
- `--time`: wall-clock time limit.
- `--output`, `--error`: stdout/stderr files.
- `--array`: job array indexes.
- `--dependency`: scheduling dependency.
- `--begin`: earliest eligible start time.
- `--signal`: request a signal before time limit or on configured conditions; check exact syntax for your version.
- `--exclusive`: request exclusive node allocation; can consume more resources than needed.
- `--export`: control environment export; can affect environment propagation.
- `--wrap`: submit a simple command string as a batch job.
- `--licenses`: site-configured license resources.
- `--clusters`: multi-cluster option, especially for `sbatch`/federations.

Do not copy options such as GPU `--gres`, account, QOS, constraints, named partitions, or node lists until you know what your cluster supports.

## Troubleshooting checklist

1. **`sbatch: command not found`** — you may not be on a Slurm client/login host.
2. **`Unable to contact slurm controller`** — check cluster access, VPN, login host, and site instructions.
3. **`Invalid account or account/partition combination`** — ask your administrator which account and partition to use.
4. **Job stays `PENDING`** — inspect `squeue -j JOB_ID` and `scontrol show job JOB_ID`; look at the pending reason.
5. **Job fails immediately** — read the `.err` file and inspect `sacct -j JOB_ID --format=JobID,State,ExitCode,Elapsed,MaxRSS`.
6. **No `sacct` data** — accounting may be disabled, delayed, or restricted.
7. **Output file not found** — remember output paths are interpreted from the submit working directory unless you specify a working directory.
8. **Memory/time limit exceeded** — reduce input size or request realistic resources within site limits.

## Suggested practice tasks

- Submit the hello job and identify its state transitions.
- Change its name and output filename.
- Request two tasks and compare task labels.
- Run the array and explain why each output file differs.
- Submit a dependent job and verify its ordering.
- Use `scontrol show job` to find the partition, requested CPUs, memory, and pending reason.
- Compare `sacct` elapsed time and memory use against your request.
- Cancel only the dedicated cancellation-demo job.
- Explain which commands are usable as a regular user and which require administrator privileges.

## References

- [Official Slurm command summary PDF](https://slurm.schedmd.com/pdfs/summary.pdf)
- [SchedMD Quick Start User Guide](https://slurm.schedmd.com/quickstart.html)
- [sbatch manual](https://slurm.schedmd.com/sbatch.html)
- [srun manual](https://slurm.schedmd.com/srun.html)
- [squeue manual](https://slurm.schedmd.com/squeue.html)

Slurm command options and site policies vary by version and configuration. The cluster administrator's documentation takes precedence.
