#!/bin/bash
echo ""
echo "Starting Storage Reclamation Patch"
echo ""
echo "Checking that this is a server node"

if [ $(sudo systemctl is-enabled rke2-server) ]; then
    echo "  This is a server node"
    echo ""
else
    echo "  FATAL: This is not a server node"
    echo "  This script should only be run on a server node"
    echo "Exiting script"
    echo ""
    exit 1
fi

echo "Generating patch.yaml file at: /tmp/patch.yaml"

if [ -f /tmp/patch.yaml ]; then
    echo "  FATAL: Patch file: /tmp/patch.yaml file already exists"
    echo "  Remove existing /tmp/patch.yaml file and re-run script"
    echo "  Command to remove file: sudo rm -rf /tmp/patch.yaml"
    echo "Exiting script"
    echo ""
    exit 1
fi

sudo cat <<'EOF' > /tmp/patch.yaml
spec:
  template:
    spec:
      containers:
      - name: longhorn-replica-folder-cleanup
        args:
        - /host
        - /bin/bash
        - -ec
        - |
          while true;
          do
            set -o pipefail
            export KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH=$PATH:/var/lib/rancher/rke2/bin:$INSTALLER_PATH
            which kubectl >> /dev/null || {
              echo "kubectl not found"
              exit 1
            }
            which jq >> /dev/null || {
              echo "jq not found"
              exit 1
            }
            directories=$(find ${LONGHORN_DISK_PATH}/replicas/ -maxdepth 1 -mindepth 1  -type d)
            for dir in $directories;
            do
              basename=$(basename "$dir")
              volume_name=${basename%-*}
              replica_name=$(kubectl -n longhorn-system get replicas.longhorn.io -o json | jq --arg dir "$basename" '.items[] | select(.spec.dataDirectoryName==$dir) | .metadata.name')
              if kubectl -n longhorn-system get volumes.longhorn.io "$volume_name" &>/dev/null;
              then
                if [[ -z ${replica_name} ]];
                then
                  robust_status=$(kubectl -n longhorn-system get volumes.longhorn.io "$volume_name" -o jsonpath='{.status.robustness}')
                  if [[ "${robust_status}" == "healthy" || "${robust_status}" == "degraded" ]];
                  then
                    echo "Replica not found but Volume found with a valid status (robust status ${robust_status}). Data directory $dir can be deleted"
                    rm -rf $dir
                  else
                    echo "Replica not found but Volume found with robust status ${robust_status}. Need to check if there is still a valid replica before deleting data directory $dir so that the directory is not required for recovery"
                  fi
                else
                  echo "Volume found and there is a replica using the data directory $dir"
                fi
              else
                if kubectl -n longhorn-system get volumes.longhorn.io "$volume_name" 2>&1 | grep "NotFound";
                then
                  echo "Volume object not found. Data directory $dir can be deleted."
                  rm -rf $dir
                else
                  echo "Could not fetch volume for $dir"
                fi
              fi
            done
            sleep 600
          done
EOF

# Checker to see if patch.yaml file was created
if [ -f /tmp/patch.yaml ]; then
    echo "  /tmp/patch.yaml file created"
    echo ""
else
    echo "  FATAL: /tmp/patch.yaml file not created"
    echo "  Previous command did not run successfully. Try running: sudo touch /tmp/patch.yaml to see why the command failed to generate the file /tmp/patch.yaml"
    echo "  If help is needed, please contact UiPath Support"
    echo "Exiting script"
    echo ""
    exit 1
fi

echo "Applying patch.yaml file"

echo '  Executing the command: sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n kube-system patch daemonset longhorn-replica-folder-cleanup --patch "$(cat /tmp/patch.yaml)"'
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n kube-system patch daemonset longhorn-replica-folder-cleanup --patch "$(cat /tmp/patch.yaml)" 1>/dev/null
exit_code=$?

echo ""

echo "Checking that the patch was applied"
if [ $exit_code -eq 0 ]; then
    echo " Patch was applied successfully"
    echo ""
else
    echo "  FATAL: Patch was not applied successfully"
    echo "  Previous command did not run successfully. Check previous errors and Contact UiPath Support for help."
    echo "  Before re-running script please run this command: sudo rm -f /tmp/patch.yaml"
    echo "Exiting script"
    echo ""
    exit 1
fi

echo "Removing /tmp/patch.yaml file"
echo ""
sudo rm -rf /tmp/patch.yaml

echo "System is patched. Make sure to run this tool in all environments on any master node"
echo ""

