# Ceph Backup and Restore Guide (Automation Suite 24.10)

Starting from version 24.10, we've introduced a new prerequisite check for configurations using a single-node RKE2 setup with in-cluster storage. A minimum 512GB additional disk is now required to store Ceph data backups.

To partition the disk for Ceph, you can use the following command:

```bash
uipathctl rke2 disk --backup-disk-name <disk-name>
```
Replace <disk-name> with the actual name of your disk (e.g., /dev/sdc).

## Ceph Backup: Configuring Hourly Backups

After the disk is partitioned, follow these steps to configure a CronJob that backs up data to the specified disk every hour.
### Step 1: Grant permissions to backup directory so backup pod can write data to it
```bash
chown 65534:65534 /backup
```
### Step 2: Navigate to the Backup Directory
```bash
cd Scripts/24.10/ceph-singlenode-backup/backup
```
### Step 3: Modify the `values.yaml`

Edit the `values.yaml` file to configure the container registry according to your setup.

### Step 4: Install the Backup Helm Chart
```bash
helm install ceph-backup . -n rook-ceph
```
This will deploy the backup CronJob, which will handle the periodic backup of your Ceph data to the specified disk.
If you run into error saying `helm` not found, you can use `/opt/UiPathAutomationSuite/UipathInstaller/bin/helm install ceph-backup . -n rook-ceph`

## Ceph Restore: Restoring Data from Backup

Follow the steps below to restore data from a previously taken Ceph backup.

### Step 1: Navigate to the Restore Directory
```bash
cd Scripts/24.10/ceph-singlenode-backup/restore
```

### Step 2: Modify `objectstore-restore-jobs.yaml`

Edit the `image` attribute in the `objectstore-restore-jobs.yaml` file to use the correct container registry according to your setup.

### Step 3: Apply the Restore Job

```bash
kubectl apply -f objectstore-restore-jobs.yaml
```

### Step 4: Monitor the Logs
You can monitor the progress of the restore operation by checking the logs of the restore job:
```bash
kubectl logs job/restore-objectstore-job -n rook-ceph
```

Following these steps will ensure that you have a reliable backup and restore process for your Ceph storage in a single-node RKE2 cluster setup. If you encounter any issues or need further assistance, please feel free to reach out.
