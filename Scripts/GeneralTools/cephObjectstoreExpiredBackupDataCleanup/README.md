# Ceph Objectstore Expired Backup Data Cleanup

> **Note:** This solution is intended for **Automation Suite v2024.10.x and v2023.10.x only**. Starting from v2025.10, this functionality is built-in and this standalone solution is not required.

## Overview

The UiPath Automation Suite backup/restore functionality stores incremental backup data of Ceph objectstore on NFS server. By default, this differential data is retained for **365 days**, regardless of the actual backup TTL (Time To Live) configuration. This means even if your Velero backups expire in a few days, their associated objectstore diff directories remain for the full 365-day period, leading to:

- **Wasted storage space** on NFS volumes
- **Continuous storage growth** with frequent scheduled backups
- **Potential out-of-space issues** in production environments

### Solution

Starting from **Automation Suite v2025.10**, this issue has been addressed with an integrated CronJob that automatically cleans up expired backup data. However, for customers running older versions (**v2024.10.x** or **v2023.10.x**), this solution provides the same functionality as a standalone deployment.

This solution deploys a Kubernetes CronJob that automatically identifies and removes:
1. Diff directories associated with **expired Velero backups** (based on TTL)
2. **Orphaned diff directories** that are no longer linked to any active backup

---

## How It Works

### Architecture

The solution consists of two Kubernetes resources:

1. **CronJob**: Schedules and executes the cleanup job periodically
2. **ConfigMap**: Contains the bash script that performs the actual cleanup logic

The script mounts your NFS volume (same as used by Velero backups) and performs intelligent cleanup by:

- Querying Velero backup CRs to understand backup lifecycle and TTL
- Analyzing diff directories at `${NFS_PATH}/objectstore/backup/s3/diff/<epoch>`
- Performing two-pass cleanup to ensure safety and prevent data loss

### Cleanup Logic

#### **Pass 1: Expired Backup Cleanup**
- Retrieves all Velero backups from the `velero` namespace
- Calculates expiry time based on backup completion time + TTL
- Identifies diff directories associated with expired backups
- Safely removes only those diff directories where:
  - The backup has completed successfully
  - All the previous backups have also expired
  - Current time > (completion time + TTL)
  - The diff directory is confirmed to belong to the expired backup

#### **Pass 2: Orphaned Diff Cleanup**
- Scans all remaining diff directories on NFS server
- Identifies orphaned directories not linked to any existing backup
- Checks if orphaned diffs are "reachable" in restoring any backup
- Removes only unreachable orphaned diffs to prevent accidental deletion of data needed by incremental backups

---

## Prerequisites

Before deploying this solution, ensure the following requirements are met:

### 1. Backup Hook Helm Chart

The backup hook chart must be installed in your cluster. This is a standard component which was installed alongside Velero and used for Automation Suite backups.

**Note:** The chart name differs between versions:
- **v2024.10.x**: `rke2-backup-hook`
- **v2023.10.x**: `backup-service`

**Verify installation:**
```bash
helm list -n uipath-infra
```

**Expected output (v2024.10.x):**
```
NAME                NAMESPACE       STATUS      CHART
rke2-backup-hook    uipath-infra    deployed    rke2-backup-hook-x.x.x
```

**Expected output (v2023.10.x):**
```
NAME                NAMESPACE       STATUS      CHART
backup-service      uipath-infra    deployed    backup-hook-x.x.x
```

### 2. ServiceAccount Permissions

The CronJob reuses the `backup-hook-sa` ServiceAccount from the backup hook chart, which has cluster-admin permissions. **No additional RBAC setup is required.**

**Verify ServiceAccount exists:**
```bash
kubectl get serviceaccount backup-hook-sa -n uipath-infra
```

### 3. NFS Server Accessibility

The NFS server used for Velero backups must be accessible from the Kubernetes cluster. The CronJob will mount the same NFS share used by your backup configuration.

---

## Installation Guide

Follow these steps to deploy the cleanup CronJob to your cluster.

### Step 1: Retrieve Required Values

Before applying the YAML, you need to collect three values from your existing cluster configuration. These values are used to replace placeholders in the YAML file.

#### 1.1 Get Container Image Name

This retrieves the same container image used by the backup hook, ensuring compatibility.

**For v2024.10.x:**
```bash
kubectl -n uipath-infra get pod -l app=rke2-backup-hook -o jsonpath='{.items[0].spec.containers[?(@.name=="backup-hook-service")].image}{"\n"}'
```

**For v2023.10.x:**
```bash
kubectl -n uipath-infra get pod -l app.kubernetes.io/part-of=backup-hook -o jsonpath='{.items[0].spec.containers[?(@.name=="backup-hook-service")].image}{"\n"}'
```

**Example output:**
```
registry.example.com/uipath/backup-hook-service:1.2.3
```

**Action:** Copy this value and replace `IMAGE_NAME_PLACEHOLDER` in the YAML file.

#### 1.2 Get NFS Server IP Address

**For v2024.10.x:**
```bash
kubectl -n uipath-infra get pod -l app=rke2-backup-hook -o jsonpath='{range .items[*].spec.volumes[?(@.nfs)]}{.nfs.server}{"\n"}{end}'
```

**For v2023.10.x:**
```bash
kubectl -n uipath-infra get pod -l app.kubernetes.io/part-of=backup-hook -o jsonpath='{range .items[*].spec.volumes[?(@.nfs)]}{.nfs.server}{"\n"}{end}'
```

**Example output:**
```
10.20.30.40
```

**Action:** Copy this value and replace `NFS_SERVER_IP_PLACEHOLDER` in the YAML file.

#### 1.3 Get NFS Export Path

**For v2024.10.x:**
```bash
kubectl -n uipath-infra get pod -l app=rke2-backup-hook -o jsonpath='{range .items[*].spec.volumes[?(@.nfs)]}{.nfs.path}{"\n"}{end}'
```

**For v2023.10.x:**
```bash
kubectl -n uipath-infra get pod -l app.kubernetes.io/part-of=backup-hook -o jsonpath='{range .items[*].spec.volumes[?(@.nfs)]}{.nfs.path}{"\n"}{end}'
```

**Example output:**
```
/asbackup
```

**Action:** Copy this value and replace `NFS_EXPORT_PATH_PLACEHOLDER` in the YAML file.

---

### Step 2: Update the YAML File

Open the `ceph-objectstore-expired-backup-data-cleanup-cronjob.yaml` file and replace the three placeholders:

```yaml
# Find and replace these placeholders with the values from Step 1:

image: IMAGE_NAME_PLACEHOLDER          # Replace with output from 1.1
server: "NFS_SERVER_IP_PLACEHOLDER"    # Replace with output from 1.2
path: "NFS_EXPORT_PATH_PLACEHOLDER"    # Replace with output from 1.3
```

**Example after replacement:**
```yaml
image: registry.example.com/uipath/backup-hook-service:1.2.3
server: "10.20.30.40"
path: "/asbackup"
```

---

### Step 3: Apply the YAML

Deploy the CronJob and ConfigMap to your cluster:

```bash
kubectl apply -f ceph-objectstore-expired-backup-data-cleanup-cronjob.yaml
```

**Expected output:**
```
cronjob.batch/ceph-objectstore-expired-backup-data-cleanup created
configmap/ceph-objectstore-expired-backup-data-cleanup created
```

---

### Step 4: Verify Deployment

#### 4.1 Check CronJob Status

```bash
kubectl get cronjobs -n uipath-infra -l cleanup-job=ceph-expired-backup-data
```

**Expected output:**
```
NAME                                           SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
ceph-objectstore-expired-backup-data-cleanup   0 2 * * 0   <none>     False     0        <none>          8s
```

#### 4.2 View ConfigMap

```bash
kubectl get configmap ceph-objectstore-expired-backup-data-cleanup -n uipath-infra
```

#### 4.3 Manual Trigger (Optional)

To manually trigger a cleanup job without waiting for the schedule:

```bash
kubectl create job --from=cronjob/ceph-objectstore-expired-backup-data-cleanup manual-cleanup-$(date +%s) -n uipath-infra
```

---

## Usage and Monitoring

### Default Schedule

The CronJob runs **weekly at 2:00 AM UTC every Sunday** (`0 2 * * 0`).

### Monitoring Job Execution

#### View All Jobs Created by the CronJob

```bash
kubectl get jobs -n uipath-infra -l cleanup-job=ceph-expired-backup-data
```

**Example output:**
```
NAME                                                   COMPLETIONS   DURATION   AGE
ceph-objectstore-expired-backup-data-cleanup-28457890  1/1           45s        2d
ceph-objectstore-expired-backup-data-cleanup-28471290  1/1           52s        1d
```

#### View Job Details

```bash
kubectl describe job <job-name> -n uipath-infra
```

#### View Logs from a Job

Replace `<job-name>` with the actual job name from the previous command:

```bash
kubectl -n uipath-infra logs -f job/<job-name>
```

**Example:**
```bash
kubectl -n uipath-infra logs -f job/ceph-objectstore-expired-backup-data-cleanup-28471290
```

### Understanding Log Output

The script provides detailed logging with timestamps:

```
[INFO] [2024-12-24T02:00:15+0000]: Validating environment and initializing...
[INFO] [2024-12-24T02:00:15+0000]: Environment validation completed successfully
[INFO] [2024-12-24T02:00:15+0000]: NFS_PATH: /asbackup
[INFO] [2024-12-24T02:00:15+0000]: DIFF_DIR: /asbackup/objectstore/backup/s3/diff
[INFO] [2024-12-24T02:00:15+0000]: VELERO_NAMESPACE: velero
[INFO] [2024-12-24T02:00:15+0000]: Collecting backups from velero namespace: velero
[INFO] [2024-12-24T02:00:16+0000]: Found 15 backups to process
[INFO] [2024-12-24T02:00:16+0000]: Processing backup: daily-backup-20241220
[INFO] [2024-12-24T02:00:18+0000]: Starting Pass 1: Delete safe expired diffs from backups
[INFO] [2024-12-24T02:00:18+0000]: Deleting expired and safe diff: /asbackup/objectstore/backup/s3/diff/1734672000 (from backup: daily-backup-20241217)
[INFO] [2024-12-24T02:00:19+0000]: Pass 1 completed: Expired diff cleanup finished
[INFO] [2024-12-24T02:00:19+0000]: Starting Pass 2: Orphaned diffs not associated with any velero backup
[INFO] [2024-12-24T02:00:20+0000]: Deleting orphaned and unreachable diff: /asbackup/objectstore/backup/s3/diff/1734500000
[INFO] [2024-12-24T02:00:20+0000]: Pass 2 completed: Orphaned diff cleanup finished
[INFO] [2024-12-24T02:00:20+0000]: Cleanup complete at Tue Dec 24 02:00:20 UTC 2024
```

---

## Configuration Options

### Adjusting the Schedule

By default, the CronJob runs **weekly on Sunday at 2 AM UTC**. To customize this:

1. Edit the `schedule` field in the YAML before applying:

```yaml
spec:
  schedule: "0 2 * * 0"  # Cron expression
```

**Common schedule examples:**
- Daily at 3 AM: `"0 3 * * *"`
- Every 6 hours: `"0 */6 * * *"`
- Weekly on Wednesday at midnight: `"0 0 * * 3"`
- Monthly on the 1st at 1 AM: `"0 1 1 * *"`

2. Update an existing CronJob:

```bash
kubectl patch cronjob ceph-objectstore-expired-backup-data-cleanup -n uipath-infra -p '{"spec":{"schedule":"0 3 * * *"}}'
```

### Adjusting Job History Retention

Control how many completed and failed jobs are kept for troubleshooting:

```yaml
spec:
  successfulJobsHistoryLimit: 3  # Keep last 3 successful jobs
  failedJobsHistoryLimit: 1      # Keep last 1 failed job
```

**To update:**
```bash
kubectl patch cronjob ceph-objectstore-expired-backup-data-cleanup -n uipath-infra -p '{"spec":{"successfulJobsHistoryLimit":5}}'
```

---

## Troubleshooting

### Job Not Running on Schedule

**Check if the CronJob is suspended:**
```bash
kubectl get cronjob ceph-objectstore-expired-backup-data-cleanup -n uipath-infra -o jsonpath='{.spec.suspend}'
```

**If output is `true`, resume it:**
```bash
kubectl patch cronjob ceph-objectstore-expired-backup-data-cleanup -n uipath-infra -p '{"spec":{"suspend":false}}'
```

### Job Failing with Permission Errors

**Check ServiceAccount exists:**
```bash
kubectl get serviceaccount backup-hook-sa -n uipath-infra
```

**Verify ServiceAccount is correctly referenced in the CronJob:**
```bash
kubectl get cronjob ceph-objectstore-expired-backup-data-cleanup -n uipath-infra -o jsonpath='{.spec.jobTemplate.spec.template.spec.serviceAccountName}'
```

### Job Failing with NFS Mount Errors

**Common error in logs:**
```
[ERROR] DIFF_DIR '/asbackup/objectstore/backup/s3/diff' does not exist. Exiting.
```

**Resolution steps:**

1. Verify NFS server is accessible from the cluster:
```bash
kubectl run -it --rm nfs-test --image=busybox --restart=Never -- ping -c 3 <NFS_SERVER_IP>
```

2. Check if NFS path is correct:

**For v2024.10.x:**
```bash
kubectl -n uipath-infra get pod -l app=rke2-backup-hook -o yaml | grep -A5 "nfs:"
```

**For v2023.10.x:**
```bash
kubectl -n uipath-infra get pod -l app.kubernetes.io/part-of=backup-hook -o yaml | grep -A5 "nfs:"
```

3. Verify the NFS export path exists on the NFS server

### No Backups Found Warning

**Log message:**
```
[WARN] No backups found in namespace velero
```

**This is normal if:**
- No backups have been created yet
- All backups have been manually deleted
- The script will still run Pass 2 to clean up any orphaned diffs

### Pod Stuck in Pending State

**Check for resource constraints:**
```bash
kubectl describe pod -l job-name=<job-name> -n uipath-infra
```

**Look for events indicating:**
- Insufficient CPU/memory resources
- Node selector/affinity issues
- Volume mount failures

---

## Uninstallation

To remove the cleanup CronJob and ConfigMap from your cluster:

```bash
kubectl delete cronjob ceph-objectstore-expired-backup-data-cleanup -n uipath-infra
kubectl delete configmap ceph-objectstore-expired-backup-data-cleanup -n uipath-infra
```

**Verify removal:**
```bash
kubectl get cronjob,configmap -n uipath-infra | grep ceph-objectstore
```

**Note:** This will NOT delete any historical jobs. To clean up completed jobs:
```bash
kubectl delete jobs -n uipath-infra -l cleanup-job=ceph-expired-backup-data
```

---

## FAQ

### Q: Will this delete active backups?
**A:** No. The script only deletes diff directories for backups that have exceeded their TTL and will never be required in restoring of any active backups. Active backups within their retention period are never touched.

### Q: What happens if I manually delete a Velero backup?
**A:** The script's Pass 2 (orphaned diff cleanup) will identify and remove the associated diff directory that is no longer linked to any backup, as long as it's not reachable from earlier backups.

### Q: Can I run this on a production cluster?
**A:** Yes. The solution is designed for production use with appropriate safety measures, resource limits, and non-root security context. However, it is advised to try this in your testing cluster first to validate that no data loss occurs.

### Q: How much storage will this free up?
**A:** It depends on your backup frequency and size. For environments with daily backups and short TTL (e.g., 7 days), this can prevent hundreds of gigabytes of unnecessary storage consumption over time.

### Q: Does this work with on-demand backups?
**A:** Yes. The script works with both scheduled and on-demand Velero backups, as long as they have a TTL configured. By default, TTL is 365 days.

### Q: What if the job fails?
**A:** The CronJob will retry up to 2 times (`backoffLimit: 2`). If all attempts fail, the failed job is kept for troubleshooting (based on `failedJobsHistoryLimit`). The next scheduled run will attempt cleanup again.

### Q: Can I customize the script logic?
**A:** It is highly recommended not to edit the script logic. Only edit configurable parameters in the CronJob based on your requirements.

---
