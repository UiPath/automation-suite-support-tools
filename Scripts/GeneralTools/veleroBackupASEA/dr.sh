#!/bin/bash

# Reconfigure DR for AS in AKS/EKS
# Applicable ASEA version: 2023.10.0-2023.10.7, 2024.10.0-2024.10.1
#
# For above mentioned version, uipathctl snapshot command doesn't create backup of volume data. This script mitigate the backup issue by reinstalling the velero and argocd configuration.
#
# Script performs below operations:
# - Re-install velero with node-agent enabled. Node-agent is required to create snapshot of file based PV
# - Updates argocd to ignore labels and annotations of deployment, statefulset and PVC resources.
# - Updates insight PVC labels to enable backup of insight data [if insight is installed]
# - Updates insight statefulset resource to enable file-based snapshot of insight data [if insight is installed]
#
# Note:
# - Before executing the script, ensure backup store is configured
# - Re-installing argocd, insight, velero and studioweb components will override the modified configuration. Please re-run this script post re-installation of these components.

set -ueo pipefail

NS_ARGOCD="${NS_ARGOCD:=argocd}"
NS_UIPATH="${NS_UIPATH:=uipath}"
NS_ISTIO="${NS_ISTIO:=istio-system}"
NS_AIRFLOW="${NS_AIRFLOW:=airflow}"
NS_MONITORING="${NS_MONITORING:=monitoring}"

REGISTRY=
REPOSITORY=
PLUGIN_NAME=
PLUGIN_IMAGE=
KUBECTL_IMAGE_TAG=
KUBECTL_IMAGE_REPO=
PROVIDER=
BUCKET=
AZURE_RG=
AZURE_ACCOUNT=
AZURE_SUBSCRIPTION_ID=
AWS_REGION=
AWS_ARN=
CREDENTIAL_SECRET_SET="false"
CREDENTIAL_SECRET_NAME="velero-azure"
VELERO_VERSION=
VELERO_CHART_VERSION=
VELERO_NODE_TOLERATIONS=

# override image if required
HELM_INSTALLER_IMAGE_TAG=

YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function error() {
  echo -e "${RED}[ERROR][$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*${NC}\n" >&2
  exit 1
}

function info() {
  echo "[INFO] [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

function warn() {
  echo -e "${YELLOW}[WARN] [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*${NC}" >&2
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# DUMP_DIR used to generate yaml files
DUMP_DIR=`mktemp -d -p "$DIR"`

if [[ ! "$DUMP_DIR" || ! -d "$DUMP_DIR" ]]; then
  error "Failed to create temporary directory"
fi

info "Using $DUMP_DIR for generating temporary files"

# clean up dump directory
function cleanup {
 	if [[ $1 -ne 0 ]]; then
		error "Command failed. Cleanup $DUMP_DIR before re-executing the script"
	fi

	rm -rf "$DUMP_DIR"
	info "Deleted temporary directory $DUMP_DIR"
}

# register the cleanup function to be called on the EXIT signal
trap 'cleanup $?' EXIT

function populate_values() {
	release_info=$(kubectl get secret -n velero   --sort-by='.metadata.creationTimestamp'  -l owner=helm,name=velero,status=deployed)
	if [[ -z "$release_info" ]]; then
		error "Velero is not installed. Install velero via uipathctl before running this script."
	fi

	if [[ -z "$HELM_INSTALLER_IMAGE_TAG" ]]; then
		HELM_INSTALLER_IMAGE_TAG=$(kubectl get secret -n uipath service-cluster-configurations  -o json |jq -r .data.CLUSTER_VERSION |base64 -d)
		if [[ "$HELM_INSTALLER_IMAGE_TAG" == "2024.10.0" ]]; then
			HELM_INSTALLER_IMAGE_TAG="1.30.5"
		elif [[ "$HELM_INSTALLER_IMAGE_TAG" == "2024.10.1" ]]; then
			HELM_INSTALLER_IMAGE_TAG="2024.10.1-1.30.5-7638190"
		elif [[ "$HELM_INSTALLER_IMAGE_TAG" == 2024.10.* ]]; then
			error "Script doesn't support DR reconfiguration for version=$HELM_INSTALLER_IMAGE_TAG"
		fi
	fi

	VELERO_VERSION=$(kubectl get deploy -n velero velero -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F 'velero/velero:' '{print $2}')

	latest_release=$(kubectl get secret -n velero   --sort-by='.metadata.creationTimestamp'  -l owner=helm,name=velero,status=deployed   -o jsonpath='{.items[-1].metadata.name}')
	release_data=$(kubectl get secret -n velero "$latest_release" -o json | jq -r .data.release | base64 -d | base64 -d | gzip -d)

	VELERO_CHART_VERSION=$(echo "$release_data" | jq -r .chart.metadata.version)

	velero_deploy_json=$(echo "$release_data" | jq -r .config)

	REPOSITORY=$(echo $velero_deploy_json | jq -r .image.repository)
	REGISTRY=$(echo $velero_deploy_json | jq -r .image.repository | sed "s/velero\/velero//g")

	PLUGIN_IMAGE=$(echo $velero_deploy_json | jq -r .initContainers[0].image)
	PLUGIN_NAME=$(echo $velero_deploy_json | jq -r .initContainers[0].name)

	KUBECTL_IMAGE_TAG=$(echo $velero_deploy_json | jq -r ".kubectl.image.tag // empty")
	KUBECTL_IMAGE_REPO=$(echo $velero_deploy_json | jq -r ".kubectl.image.repository")

	azure_secret=$(echo $velero_deploy_json | jq -r ".credentials // empty")
	if [[ ! -z "$azure_secret" ]]; then
		use_secret=$(echo $velero_deploy_json | jq -r .credentials.useSecret)
		if [[ "$use_secret" == "true" ]]; then
			CREDENTIAL_SECRET_SET="true"
			CREDENTIAL_SECRET_NAME=$(echo $velero_deploy_json | jq -r .credentials.existingSecret)
		fi
	fi

	if [[ "$VELERO_CHART_VERSION" == 3.1* ]]; then
		PROVIDER=$(echo $velero_deploy_json | jq -r .configuration.provider)
		BUCKET=$(echo $velero_deploy_json |jq -r .configuration.backupStorageLocation.bucket)
	else
		PROVIDER=$(echo $velero_deploy_json | jq -r .configuration.backupStorageLocation[0].provider)
		BUCKET=$(echo $velero_deploy_json |jq -r .configuration.backupStorageLocation[0].bucket)
	fi

	if [[ "$PROVIDER" == "azure" ]]; then
		if [[ "$VELERO_CHART_VERSION" == 3.1* ]]; then
			AZURE_RG=$(echo $velero_deploy_json |jq -r .configuration.backupStorageLocation.config.resourceGroup)
			AZURE_ACCOUNT=$(echo $velero_deploy_json |jq -r .configuration.backupStorageLocation.config.storageAccount)
			AZURE_SUBSCRIPTION_ID=$(echo $velero_deploy_json |jq -r .configuration.backupStorageLocation.config.subscriptionId)
		else
			AZURE_RG=$(echo $velero_deploy_json |jq -r .configuration.backupStorageLocation[0].config.resourceGroup)
			AZURE_ACCOUNT=$(echo $velero_deploy_json |jq -r .configuration.backupStorageLocation[0].config.storageAccount)
			AZURE_SUBSCRIPTION_ID=$(echo $velero_deploy_json |jq -r .configuration.backupStorageLocation[0].config.subscriptionId)
		fi
	else
		AWS_ARN=$(echo $velero_deploy_json |jq -r ".serviceAccount.server.annotations // empty" | jq -r '."eks.amazonaws.com/role-arn" // empty')
		if [[ "$VELERO_CHART_VERSION" == 3.1* ]]; then
			AWS_REGION=$(echo $velero_deploy_json |jq -r .configuration.backupStorageLocation.config.region)
		else
			AWS_REGION=$(echo $velero_deploy_json |jq -r .configuration.backupStorageLocation[0].config.region)

		fi
	fi

	tolerations=$(echo $velero_deploy_json |jq -r -c ".tolerations // empty" | sed -e "s/tolerationseconds/tolerationSeconds/g")
	if [[ ! -z "$tolerations" ]]; then
		VELERO_NODE_TOLERATIONS=$tolerations
 	fi
}

configMapBaseTemplate="apiVersion: v1
kind: ConfigMap
metadata:
  name: helm-values-velero-manual
  namespace: uipath-installer
data:
  values.yaml: |
    image:
      repository: REPOSITORY_VALUE
    initContainers:
      - name: PLUGIN_NAME_VALUE
        image: PLUGIN_IMAGE_VALUE
        imagePullPolicy: IfNotPresent
        volumeMounts:
          - mountPath: /target
            name: plugins
    backupsEnabled: true
    snapshotsEnabled: true
    deployNodeAgent: true
    serviceAccount:
      server:
        annotations: {}
    kubectl:
      image:
        repository: KUBECTL_IMAGE_REPO_VALUE
        tag: KUBECTL_IMAGE_TAG_VALUE
"

configMapCredTemplate="    credentials:
      useSecret: true
      existingSecret: CREDENTIAL_SECRET_NAME_VALUE
"

# azure template for velero version 3.1.x
configMapAZURETemplate_3_1="    configuration:
      provider: azure
      backupStorageLocation:
        name: default-bsl
        bucket: BUCKET_VALUE
        config:
          resourceGroup: AZURE_RG_VALUE
          subscriptionId: AZURE_SUBSCRIPTION_ID_VALUE
          storageAccount: AZURE_ACCOUNT_VALUE
      volumeSnapshotLocation:
        name: default-vsl
        config:
          resourceGroup: AZURE_RG_VALUE
          subscriptionId: AZURE_SUBSCRIPTION_ID_VALUE
"

configMapAZURETemplate="    configuration:
      backupStorageLocation:
        - bucket: BUCKET_VALUE
          config:
            resourceGroup: AZURE_RG_VALUE
            storageAccount: AZURE_ACCOUNT_VALUE
            subscriptionId: AZURE_SUBSCRIPTION_ID_VALUE
          name: default-bsl
          provider: azure
      volumeSnapshotLocation:
        - config:
            resourceGroup: AZURE_RG_VALUE
            subscriptionId: AZURE_SUBSCRIPTION_ID_VALUE
          name: default-vsl
          provider: azure
"

# AWS template for velero version 3.1.x
configMapAWSTemplate_3_1="    configuration:
      provider: aws
      backupStorageLocation:
        name: default-bsl
        bucket: BUCKET_VALUE
        config:
          region: AWS_REGION_VALUE
      volumeSnapshotLocation:
        name: default-vsl
        config:
          region: AWS_REGION_VALUE
"

configMapAWSTemplate="    configuration:
      backupStorageLocation:
        - bucket: BUCKET_VALUE
          config:
            region: AWS_REGION_VALUE
          name: default-bsl
          provider: aws
      volumeSnapshotLocation:
        - config:
            region: AWS_REGION_VALUE
          name: default-vsl
          provider: aws
"

configMapAWSSATemplate="    serviceAccount:
      server:
        annotations:
          eks.amazonaws.com/role-arn : \"AWS_ARN_VALUE\"
"

configMapTolerationTemplate="    tolerations: TOLERATIONS_VALUE"
configMapNodeAgentTolerationTemplate="    nodeAgent:
      tolerations: TOLERATIONS_VALUE
"

create_config_map() {
	parsedConfigMapBase=$(echo "$configMapBaseTemplate" |	\
		sed -e "s|REPOSITORY_VALUE|$REPOSITORY|g" 	\
		-e "s|PLUGIN_NAME_VALUE|$PLUGIN_NAME|g"	\
		-e "s|PLUGIN_IMAGE_VALUE|$PLUGIN_IMAGE|g"	\
		-e "s|KUBECTL_IMAGE_REPO_VALUE|$KUBECTL_IMAGE_REPO|g"	\
		-e "s|KUBECTL_IMAGE_TAG_VALUE|$KUBECTL_IMAGE_TAG|g"	\
		)

	parsedConfigMapCred=
	if [[ "$CREDENTIAL_SECRET_SET" == "true" ]]; then
		parsedConfigMapCred=$(echo "$configMapCredTemplate" | sed -e "s|CREDENTIAL_SECRET_NAME_VALUE|$CREDENTIAL_SECRET_NAME|g")
	fi

	parsedConfigMapAZURE=
	if [[ "$PROVIDER" == "azure" ]]; then
		if [[ "$VELERO_CHART_VERSION" == 3.1* ]]; then
			parsedConfigMapAZURE=$(echo "$configMapAZURETemplate_3_1" |	\
				sed -e "s|BUCKET_VALUE|$BUCKET|g"	\
				-e "s|AZURE_RG_VALUE|$AZURE_RG|g"	\
				-e "s|AZURE_SUBSCRIPTION_ID_VALUE|$AZURE_SUBSCRIPTION_ID|g"	\
				-e "s|AZURE_ACCOUNT_VALUE|$AZURE_ACCOUNT|g"	\
				)
		else
			parsedConfigMapAZURE=$(echo "$configMapAZURETemplate" |	\
				sed -e "s|BUCKET_VALUE|$BUCKET|g"	\
				-e "s|AZURE_RG_VALUE|$AZURE_RG|g"	\
				-e "s|AZURE_SUBSCRIPTION_ID_VALUE|$AZURE_SUBSCRIPTION_ID|g"	\
				-e "s|AZURE_ACCOUNT_VALUE|$AZURE_ACCOUNT|g"	\
				)
		fi
	fi

	parsedConfigMapAWS=
	if [[ "$PROVIDER" == "aws" ]]; then
		if [[ "$VELERO_CHART_VERSION" == 3.1* ]]; then
			parsedConfigMapAWS=$(echo "$configMapAWSTemplate_3_1" | \
				sed -e "s|BUCKET_VALUE|$BUCKET|g"	\
				-e "s|AWS_REGION_VALUE|$AWS_REGION|g"	\
				)
		else
			parsedConfigMapAWS=$(echo "$configMapAWSTemplate" | \
				sed -e "s|BUCKET_VALUE|$BUCKET|g"	\
				-e "s|AWS_REGION_VALUE|$AWS_REGION|g"	\
				)
		fi
	fi

	parsedConfigMapAWSSA=
	if [[ "$PROVIDER" == "aws" && ! -z "$AWS_ARN" ]]; then
		parsedConfigMapAWSSA=$(echo "$configMapAWSSATemplate" | \
			sed -e "s|AWS_ARN_VALUE|$AWS_ARN|g"	\
			)
	fi

	parsedConfigMapTolerations=
	parsedConfigMapNodeAgentTolerations=
	if [[ ! -z "$VELERO_NODE_TOLERATIONS" ]]; then
		parsedConfigMapTolerations=$(echo "$configMapTolerationTemplate" | \
			sed -e "s|TOLERATIONS_VALUE|$VELERO_NODE_TOLERATIONS|g"	\
			)
		parsedConfigMapNodeAgentTolerations=$(echo "$configMapNodeAgentTolerationTemplate" | \
			sed -e "s|TOLERATIONS_VALUE|$VELERO_NODE_TOLERATIONS|g"	\
			)
	fi

	# Building the final configmap
	finalConfigMap=$(echo "$parsedConfigMapBase")
	if [[ ! -z "$parsedConfigMapCred" ]]; then
		finalConfigMap=$(echo "$finalConfigMap"; echo "$parsedConfigMapCred")
	fi

	if [[ "$PROVIDER" == "azure" ]]; then
		finalConfigMap=$(echo "$finalConfigMap"; echo "$parsedConfigMapAZURE")
	else
		finalConfigMap=$(echo "$finalConfigMap"; echo "$parsedConfigMapAWS")
	fi

	if [[ ! -z "$parsedConfigMapAWSSA" ]] && [[ "$PROVIDER" == "aws" ]]; then
		finalConfigMap=$(echo "$finalConfigMap"; echo "$parsedConfigMapAWSSA")
	fi

	if [[ ! -z "$parsedConfigMapAWSSA" ]] && [[ "$PROVIDER" == "aws" ]]; then
		finalConfigMap=$(echo "$finalConfigMap"; echo "$parsedConfigMapAWSSA")
	fi

	if [[ ! -z "$parsedConfigMapTolerations" ]] && [[ ! -z "$parsedConfigMapNodeAgentTolerations" ]]; then
		finalConfigMap=$(echo "$finalConfigMap"; echo "$parsedConfigMapTolerations")
		finalConfigMap=$(echo "$finalConfigMap"; echo "$parsedConfigMapNodeAgentTolerations")
	fi

	configmap_file=$(mktemp --tmpdir=$DUMP_DIR --suffix=.configmap.yaml)
	echo "$finalConfigMap" >> $configmap_file
	kubectl apply -f "${configmap_file}"
}

install_velero() {
	#delete old install-velero-manual pod
	kubectl delete pod -n uipath-installer install-velero-manual --ignore-not-found

	tolerations="null"
	if [[ ! -z "$VELERO_NODE_TOLERATIONS" ]]; then
		tolerations=$VELERO_NODE_TOLERATIONS
	fi

	helm_installer_file=$(mktemp --tmpdir=$DUMP_DIR --suffix=.helm-installer.yaml)
cat >"${helm_installer_file}" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: helm-installer-manual
  namespace: uipath-installer
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: helm-installer
rules:
- apiGroups:
  - '*'
  resources:
  - '*'
  verbs:
  - '*'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: helm-installer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: helm-installer
subjects:
- kind: ServiceAccount
  name: helm-installer-manual
  namespace: uipath-installer
---
apiVersion: v1
kind: Pod
metadata:
  labels:
    app.kubernetes.io/instance: helm-install-velero
    app.kubernetes.io/name: helm-install
  name: install-velero-manual
  namespace: uipath-installer
spec:
  containers:
  - args:
    - upgrade
    - --install
    - velero
    - /opt/app-root/charts/velero
    - --namespace
    - velero
    - --wait
    - --timeout
    - 30m0s
    - --values
    - /data/values.yaml
    - --debug
    command:
    - helm
    env:
    - name: HELM_CACHE_HOME
      value: /workdir
    image: ${REGISTRY}helm-installer:${HELM_INSTALLER_IMAGE_TAG}
    imagePullPolicy: IfNotPresent
    name: helm
    resources: {}
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
        - NET_RAW
      privileged: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
    terminationMessagePath: /dev/termination-log
    terminationMessagePolicy: File
    volumeMounts:
    - mountPath: /workdir
      name: workdir
    - mountPath: /data
      name: values
      readOnly: true
    workingDir: /workdir
  dnsPolicy: ClusterFirst
  enableServiceLinks: true
  imagePullSecrets:
  - name: uipathpullsecret
  priority: 0
  restartPolicy: Never
  schedulerName: default-scheduler
  securityContext:
    fsGroup: 3000
    runAsGroup: 2000
    runAsNonRoot: true
    runAsUser: 1000
  serviceAccount: helm-installer-manual
  serviceAccountName: helm-installer-manual
  tolerations: $tolerations
  volumes:
  - emptyDir: {}
    name: workdir
  - configMap:
      defaultMode: 420
      name: helm-values-velero-manual
    name: values
EOF

	kubectl apply -f "${helm_installer_file}"
	#wait for installer pod to complete
	kubectl wait -n uipath-installer pod install-velero-manual --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s

	phase=$(kubectl get pods -n uipath-installer install-velero-manual -o json |jq -r .status.phase)
	if [[ "$phase" == "Succeeded" ]]; then
		info "Velero installation completed successfully"

		info "Deleting generated resources"

		kubectl delete pods -n uipath-installer install-velero-manual
		kubectl delete configmap -n uipath-installer helm-values-velero-manual
		kubectl delete clusterrolebinding -n uipath-installer helm-installer
		kubectl delete clusterrole -n uipath-installer helm-installer
		kubectl delete serviceaccount -n uipath-installer helm-installer-manual
	else
		error "Velero installation $phase, please check logs: kubectl logs -n uipath-installer install-velero-manual"
	fi
}

# modify component configuration for backup
modify_configuration() {
	info "Updating argo-cd configuration"

	kubectl patch cm -n argocd argocd-cm -p '{"data":{"resource.customizations.ignoreDifferences.PersistentVolumeClaim": "jsonPointers:\n- '/metadata/labels/velero.io~1exclude-from-backup'\n"}}'

	kubectl patch cm -n argocd argocd-cm -p '{"data":{"resource.customizations.ignoreDifferences.apps_Statefulset": "jsonPointers:\n- '/spec/template/metadata/annotations/backup.velero.io~1backup-volumes'\n"}}'

	kubectl patch cm -n argocd argocd-cm -p '{"data":{"resource.customizations.ignoreDifferences.apps_Deployment": "jsonPointers:\n- '\'/spec/template/metadata/annotations/backup.velero.io~1backup-volumes\''\n- '\'/spec/template/metadata/labels/velero.io~1exclude-from-backup\''\n"}}'
	kubectl rollout restart sts/argocd-application-controller -n argocd

	if kubectl get sts -n uipath insights-insightslooker; then
		info "Updating resources of insight"
		kubectl label pvc -n uipath insights-looker-lookerdir-pvc velero.io/exclude-from-backup=false --overwrite
		kubectl label pvc -n uipath insights-looker-datadir-pvc velero.io/exclude-from-backup=false --overwrite
		kubectl patch sts -n uipath insights-insightslooker -p '{"spec": {"template": {"metadata": {"annotations": {"backup.velero.io/backup-volumes":"insights-looker-lookerdir,insights-looker-workdir"}}}}}'
		kubectl rollout status sts/insights-insightslooker -n uipath
	fi

	if kubectl get deploy -n uipath studioweb-typecache; then
		info "Updating resources of studioweb-typecache"
		kubectl label pvc -n uipath studioweb-backend-pvc velero.io/exclude-from-backup=false --overwrite
		kubectl patch deploy -n uipath studioweb-typecache -p '{"spec": {"template": {"metadata": {"annotations": {"backup.velero.io/backup-volumes":"pvc-volume"}}}}}'
		kubectl patch deploy -n uipath studioweb-typecache -p '{"spec": {"template": {"metadata": {"labels": {"velero.io/exclude-from-backup":"false"}}}}}'
		kubectl rollout status deploy/studioweb-typecache -n uipath
	fi

	if kubectl get deploy -n uipath studioweb-backend; then
		info "Updating resources of studioweb-backend"
		kubectl label pvc -n uipath studioweb-backend-pvc velero.io/exclude-from-backup=false --overwrite
		kubectl patch deploy -n uipath studioweb-backend -p '{"spec": {"template": {"metadata": {"annotations": {"backup.velero.io/backup-volumes":"pvc-volume"}}}}}'
		kubectl patch deploy -n uipath studioweb-backend -p '{"spec": {"template": {"metadata": {"labels": {"velero.io/exclude-from-backup":"false"}}}}}'
		kubectl rollout status deploy/studioweb-backend -n uipath
	fi

# No need to create backup of asrobot cached data. Enable below block if required.
#	if kubectl get deploy -n uipath asrobots-pkg-cache; then
#		info "Updating resources of asrobot"
#		kubectl label pvc -n uipath asrobots-pvc-package-cache velero.io/exclude-from-backup=false --overwrite
#		kubectl patch deploy -n uipath asrobots-pkg-cache -p '{"spec": {"template": {"metadata": {"annotations": {"backup.velero.io/backup-volumes":"packagedir"}}}}}'
#		kubectl patch deploy -n uipath asrobots-pkg-cache -p '{"spec": {"template": {"metadata": {"labels": {"velero.io/exclude-from-backup":"false"}}}}}'
#		kubectl rollout status deploy/asrobots-pkg-cache -n uipath
#	fi
}

# check if binary exist
binary_exists() {
	command -v "$1" >/dev/null 2>&1
}

# check prereq for utility
check_prereq() {
	missing_cli=()
	required_cli=( kubectl date jq awk base64 gzip sed getopt )
	for binary in "${required_cli[@]}"; do
		if ! binary_exists "$binary"; then
			missing_cli+=( "$binary" )
		fi
	done

	if [[ ${#missing_cli[@]} -ne 0 ]]; then
		error "Please install $(IFS=, ; echo "${missing_cli[*]}") binary to execute the script"
	fi
}

# re-install velero with node-agent
reinstall_velero() {
	check_prereq

	info "Re-configuring velero"

	# set pre-defined variables from installed velero release
	populate_values

	# create helm configmap to install velero
	create_config_map

	# create helm installer pod
	install_velero

	# modify configuration
	modify_configuration
}

# create velero backup resource
create_backup() {
	check_prereq

	if [[ $# -ne 1 ]]; then
		error "Missing backup name"
	fi
	name=$1

	info "Creating backup=$name"
	VELERO_VERSION=$(kubectl get deploy -n velero velero -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F 'velero/velero:' '{print $2}')

	backup_file=$(mktemp --tmpdir=$DUMP_DIR --suffix=.backup.yaml)
	if [[ "$VELERO_VERSION" == v1.10.* ]]; then
cat >"${backup_file}" <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  annotations:
  labels:
    velero.io/storage-location: default-bsl
  name: $name
  namespace: velero
spec:
  csiSnapshotTimeout: 10m0s
  defaultVolumesToFsBackup: false
  includedNamespaces:
  - $NS_ARGOCD
  - $NS_UIPATH
  - $NS_ISTIO
  - $NS_AIRFLOW
  - $NS_MONITORING
  snapshotVolumes: true
  storageLocation: default-bsl
  ttl: 8760h0m0s
  volumeSnapshotLocations:
  - default-vsl
EOF
	else
cat >"${backup_file}" <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  annotations:
  labels:
    velero.io/storage-location: default-bsl
  name: $name
  namespace: velero
spec:
  csiSnapshotTimeout: 10m0s
  defaultVolumesToFsBackup: false
  includedNamespaces:
  - $NS_ARGOCD
  - $NS_UIPATH
  - $NS_ISTIO
  - $NS_AIRFLOW
  - $NS_MONITORING
  snapshotVolumes: true
  storageLocation: default-bsl
  ttl: 8760h0m0s
  includedClusterScopedResources:
  - mutatingwebhookconfigurations
  - storageclass
  volumeSnapshotLocations:
  - default-vsl
EOF
	fi

	kubectl apply -f "${backup_file}"
	IFS=" " read -r -a sc <<<$(kubectl get pv  -o jsonpath="{.items[*].spec.storageClassName}")

	info "Backup=$name created"
	info "Run \`uipathctl snapshot list\` command to check backup status"
	info ""
	warn "Note: To restore backup=$name in target cluster:"
	warn "	- Please ensure storageclass $(IFS=, ; echo "${sc[*]}") exists in target cluster"
	warn "	- After restoring the backup in target cluster, Install istiod component via uipathctl"
	warn "  - Post installation of istiod, run \`kubectl  rollout restart deploy/istiod -n istio-system\'"
}

display_usage() {
	echo "usage: $(basename "$0") [command]"
	echo "Options:
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
"
}

set +e
args=$(getopt -o ihb: --long install,backup:,help -- "$@")
if [[ $? -ne 0 ]]; then
    display_usage;
    exit 1
fi
set -e

eval set -- "$args"
while [ : ]; do
  case "$1" in
    -i | --install)
	reinstall_velero
	break
        ;;
    -b | --backup)
	create_backup "$2"
	break
        ;;
    -h | --help)
        display_usage
	break
        ;;
    --) shift;
        display_usage
        break
        ;;
  esac
done
