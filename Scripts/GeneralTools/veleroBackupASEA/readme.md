# Re-configure ASEA DR for 23.10.x and 24.10.x

Applicable ASEA version: 2023.10.0-2023.10.7, 2024.10.0-2024.10.1

For above mentioned version, uipathctl snapshot command doesn't create backup of volume data. This script mitigate the backup issue by reinstalling the velero and argocd configuration.

Script performs below operations:
 - Re-install velero with node-agent enabled. Node-agent is required to create snapshot of file based PV
 - Updates argocd to ignore labels and annotations of deployment, statefulset and PVC resources.# - Updates insight PVC labels to enable backup of insight data [if insight is installed]
 - Updates insight statefulset resource to enable file-based snapshot of insight data [if insight is installed]

 Note:
 - Before executing the script, ensure velero is installed
 - Re-installing argocd, insight, velero and studioweb components will override the modified configuration. Please re-run this script post re-installation of these components.


 ## Usage
usage: dr.sh [command]
Options:
	-i, --install:
            Install DR solution. Command will re-install velero and modify required configuration in cluster to create backup of persistent storage.
            This modification includes:
                - Patching insight statefulset resource to generate file-based backup of insight volumes
                - Patching studioweb deployment resource to generate file-based backup of studioweb volumes
                - Patching required volumes to includes it in backup
                - Updating argocd configuration to disable overriding of above modifications

        -b, --backup <backup-name>:
            Create backup of cluster.
            Backup will be created for argocd, uipath, istio, airflow, monitoring namespace.

            If cluster is using different namespace instead of standard one,
            then export below variables to map relevant namespace:
              NS_ARGOCD => for argocd namespace
              NS_UIPATH => for uipath namespace
              NS_AIRFLOW => for airflow namespace
              NS_MONITORING => for monitoring namespace

        -h, --help:
            Display usage of utility

## Example
### To re-configure velero installation
```
./dr.sh -i
```

### To take snapshot of cluster
```
./dr.sh -b backup0
```

## To restore the backup in target cluster
For AS version 23.10.x, ensure storageclass from source cluster are created in target cluster. List of the required storageclass can be found in the output of `./dr.sh -b backup0` command.

To restore the snapshot, run below command:
```
./uipathctl snapshot restore create <restore_name> --from-snapshot <snapshot_name>
```
