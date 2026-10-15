#!/usr/bin/env bash
set -u
echo "== sacct: recent jobs for this user =="
sacct --user="$USER" --starttime=now-1day --format=JobID,JobName,Partition,State,ExitCode,Elapsed,AllocCPUS,MaxRSS 2>&1 || true
echo
echo "== sprio: priority details (may be site-dependent) =="
sprio --user="$USER" 2>&1 || true
echo
echo "== sshare: fair-share (may be site-dependent) =="
sshare --user="$USER" 2>&1 || true
echo
echo "== sreport: a small cluster utilisation report (may require permissions/configuration) =="
sreport cluster utilization start=now-1days end=now 2>&1 || true
echo
echo "== sstat: live usage example =="
echo "Choose a currently RUNNING job ID from squeue, then run:"
echo "sstat -j JOB_ID --format=JobID,AveCPU,MaxRSS,MaxVMSize"
echo
echo "Accounting commands may return no data or errors when accounting is not enabled or access is restricted."
