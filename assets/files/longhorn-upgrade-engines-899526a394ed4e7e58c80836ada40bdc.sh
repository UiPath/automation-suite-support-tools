#!/bin/bash

set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -z "${SCRIPT_DIR}" ]]; then
  error "Could not determine script path"
fi

readonly SCRIPT_DIR

function info() {
  echo "[INFO] [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

function warn() {
  echo -e "\e[0;33m[WARN] [$(date +'%Y-%m-%dT%H:%M:%S%z')]:\e[0m $*" >&2
}

function error() {
  echo -e "\e[0;31m[ERROR][$(date +'%Y-%m-%dT%H:%M:%S%z')]:\e[0m $*" >&2
  exit 1
}

function wait_volume_healthy(){
  pv_name=$1
  local try=0
  local maxtry=30
  local success=0
  while (( try < maxtry ));do
    status=$(kubectl -n longhorn-system get volumes.longhorn.io "${pv_name}"  -o json |jq -r ".status.state") || true
    info "volume ${pv_name} status: ${status}"
    if [[ "${status}" == "detached" ]]; then
      success=1
      info "Volume ready to use"
      break
    fi
    info "waiting for volume to be ready to use${try}/${maxtry}..."; sleep 30
    try=$(( try + 1 ))
  done

  export WAIT_VOLUME_HEALTHY="${success}"
}

function scale_ownerreferences() {
  local ownerReferences=$1
  local namespace=$2
  local replicas=$3

  # no operation required
  if [[ -z "${ownerReferences}" || "${ownerReferences}" == "null" ]]; then
    return
  fi

  ownerReferences=$(echo "${ownerReferences}"| jq -c ".[]")
  for ownerReference in ${ownerReferences};
  do
    echo "Owner: ${ownerReference}"
    local resourceKind
    local resourceName
    resourceKind=$(echo "${ownerReference}"| jq -r ".kind")
    resourceName=$(echo "${ownerReference}"| jq -r ".name")

    if kubectl -n "${namespace}" get "${resourceKind}" "${resourceName}" >/dev/null 2>&1; then
      # scale replicas
      kubectl  -n "${namespace}" patch "${resourceKind}" "${resourceName}" --type json -p "[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": ${replicas} }]"
    fi
  done
}

function set_longhorn_url(){
  local node_role=${1:-none}
  local longhorn_svc
  local longhorn_ip
  local longhorn_port

  get_cmd_for_node_role_result=""
  longhorn_svc_cmd="kubectl -n longhorn-system get svc longhorn-backend -o=json"

  # get longhorn backend ip & port
  longhorn_svc=$(${longhorn_svc_cmd} | jq -c '.spec| {ip: .clusterIP, port: .ports[0].port}')
  longhorn_ip=$(echo "${longhorn_svc}"| jq -r ".ip")
  longhorn_port=$(echo "${longhorn_svc}"| jq -r ".port")

  if [[ -z "${longhorn_ip}" || -z "${longhorn_port}" ]]; then
    error "Failed to set Longhorn RestApi Endpoint"
  fi
  LONGHORN_URL="http://${longhorn_ip}:${longhorn_port}"

  export LONGHORN_URL="${LONGHORN_URL}"
  info "Longhorn RestApi Endpoint: ${LONGHORN_URL}"
}

function get_latest_engine_image() {
  local version=$1
  local engine_images
  local image
  local try=0
  local maxtry=10
  while (( try != maxtry )) ; do
    engine_images=$(curl "${LONGHORN_URL}/v1/engineimages?") || true
    if [[ -n "${engine_images}" && -n $(echo "${engine_images}"|jq -r ".data[]") ]]; then
      image=$(echo "${engine_images}"|jq -r ".data[]|select(.version == \"${version}\").image")
      if [[ -n "${image}" ]]; then
        export LATEST_ENGINE_IMAGE="${image}"
        break;
      fi
    fi
    try=$((try+1))
    info "waiting for getting upgraded engine image details...${try}/${maxtry}"; sleep 30
  done
}

function get_current_pvc_engine() {
  local pv_name=$1
  local volume
  local engine_image

  volume=$(curl "${LONGHORN_URL}/v1/volumes/${pv_name}?") || true
  engine_image=$(echo "${volume}"|jq -r ".currentImage")

  export CURRENT_PVC_ENGINE="${engine_image}"
}

function upgrade_pvc_engine() {
  local pv_name=$1
  local engine_image=$2

  success=0
  if [[ -z "${engine_image}" ]]; then
    return
  fi

  local upgrade_resp
  upgrade_resp=$(curl "${LONGHORN_URL}/v1/volumes/${pv_name}?action=engineUpgrade"  --data-raw "{\"image\":\"${LATEST_ENGINE_IMAGE}\"}") || true
  if [[ -n "${upgrade_resp}" && "${upgrade_resp}" != "null" && -n $(echo "${upgrade_resp}"| jq -c ".id") ]]; then
    info "Upgrade Response: ${upgrade_resp}"
    wait_volume_healthy "${pv_name}"
    if [[ "${WAIT_VOLUME_HEALTHY}" -eq 1 ]]; then
      success=1
      unset WAIT_VOLUME_HEALTHY
    fi
  fi

  export UPGRADE_PVC_ENGINE_RESP=${success}
}

function scale_down_deployment(){
  local deployment_name=$1
  local namespace=$2

  info "Start Scale Down deployment ${deployment_name} under namespace ${namespace}..."
  info "Waiting to scale down deployment..."

  local try=0
  local maxtry=60
  success=0
  while (( try != maxtry )) ; do
    result=$(kubectl scale deployment "${deployment_name}" --replicas=0 -n "${namespace}") || true
    info "${result}"
    scaledown=$(kubectl get deployment "${deployment_name}" -n "${namespace}"|grep 0/0) || true
    if { [ -n "${scaledown}" ] && [ "${scaledown}" != " " ]; }; then
      info "Deployment scaled down successfully."
      success=1
      break
    else
      try=$((try+1))
      info "waiting for the deployment ${deployment_name} to scale down...${try}/${maxtry}";sleep 30
    fi
  done

  if [ ${success} -eq 0 ]; then
    warn "Deployment ${deployment_name} scaled down failed"
  fi
}

function scale_up_deployment() {
  local deployment_name=$1
  local namespace=$2
  local replica=$3

  # Scale up deployments using PVCs
  info "Start Scale Up deployment ${deployment_name}..."

  info "Waiting to scale up deployment..."

  local try=1
  local maxtry=15
  success=0
  while (( try != maxtry )) ; do
    result=$(kubectl scale deployment "${deployment_name}" --replicas="${replica}" -n "${namespace}") || true
    info "${result}"

    scaleup=$(kubectl get deployment "${deployment_name}" -n "${namespace}"|grep "${replica}"/"${replica}") || true
    if ! { [ -n "${scaleup}" ] && [ "${scaleup}" != " " ]; }; then
      try=$((try+1))
      info "waiting for the deployment ${deployment_name} to scale up...${try}/${maxtry}";sleep 30
    else
      info "Deployment scaled up successfully."
      success=1
      break
    fi
  done

  if [ ${success} -eq 0 ]; then
    warn "Deployment scaled up failed ${deployment_name}."
  fi
}

function upgrade_engine_image_for_pvc_attached_to_deployments() {
  local deployment_list

  # list of all deployment using PVC
  deployment_list=$(kubectl get deployments -A -o=json | jq -c ".items[] |\
{name: .metadata.name, namespace: .metadata.namespace, replicas: .spec.replicas, pvcList:.spec.template.spec |\
[select( has (\"volumes\") ).volumes[] |\
select( has (\"persistentVolumeClaim\") ).persistentVolumeClaim.claimName]|select(length > 0) }")

  for deployment in ${deployment_list};
  do
    deployment_name=$(echo "${deployment}"| jq -r ".name")
    pvc_list=$(echo "${deployment}"| jq -r ".pvcList[]")
    namespace=$(echo "${deployment}"| jq -r ".namespace")
    replica=$(echo "${deployment}" | jq -r ".replicas")
    local upgrade_required=0

    for pvc_name in ${pvc_list};
    do
      # get pv for pvc
      get_pvc_resources_resp=""
      get_pvc_resources "${pvc_name}" "${namespace}"

      local pv_name
      pv_name=$(echo "${get_pvc_resources_resp}"| jq -r ".pv_name")

      get_current_pvc_engine "${pv_name}"
      if [[ "${LATEST_ENGINE_IMAGE}" == "${CURRENT_PVC_ENGINE}" ]]; then
        info "PVC volume already upgraded to new engine image ${CURRENT_PVC_ENGINE}"
        continue
      fi

      upgrade_required=1
    done

    if [ "${upgrade_required}" == 0 ]; then
      continue
    fi

    info "deployment $deployment_name is having issue"
    scale_down_deployment "${deployment_name}" "${namespace}"

    for pvc_name in ${pvc_list};
    do
      upgrade_pvc_engine "${pv_name}" "${CURRENT_PVC_ENGINE}"

      if [[ "${UPGRADE_PVC_ENGINE_RESP}" -eq 0 ]]; then
        scale_up_deployment "${deployment_name}" "${namespace}" "${replica}"
        error "Upgrade failed for pvc ${pvc_name}, rollback deployment ${deployment_name}."
      fi
      unset UPGRADE_PVC_ENGINE_RESP
    info "Successfully upgraded engine image for pvc ${pvc_name}"
    done

    unset CURRENT_PVC_ENGINE
    scale_up_deployment "${deployment_name}" "${namespace}" "${replica}"
    sleep 5
  done
}

function scale_down_statefulset() {
  local statefulset_name=$1
  local namespace=$2
  local ownerReferences=$3

  info "Start Scale Down statefulset ${statefulset_name} under namespace ${namespace}..."

  # validate and scale down ownerreference
  scale_ownerreferences "${ownerReferences}" "${namespace}" 0

  local try=0
  local maxtry=30
  success=0
  while (( try != maxtry )) ; do
    result=$(kubectl scale statefulset "${statefulset_name}" --replicas=0 -n "${namespace}") || true
    info "${result}"
    scaledown=$(kubectl get statefulset "${statefulset_name}" -n "${namespace}"|grep 0/0) || true
    if { [ -n "${scaledown}" ] && [ "${scaledown}" != " " ]; }; then
      info "Statefulset scaled down successfully."
      success=1
      break
    else
      try=$((try+1))
      info "waiting for the statefulset ${statefulset_name} to scale down...${try}/${maxtry}";sleep 30
    fi
  done

  if [ ${success} -eq 0 ]; then
    warn "Statefulset ${statefulset_name} scaled down failed"
  fi
}

function upgrade_engine_image_for_pvc_attached_to_statefulsets() {
    local statefulset_list

  # list of all statefulset using PVC
  statefulset_list=$(kubectl get statefulset -A -o=json | jq -c ".items[] |\
{name: .metadata.name, namespace: .metadata.namespace, replicas: .spec.replicas, claimName:.spec |\
select( has (\"volumeClaimTemplates\") ).volumeClaimTemplates[].metadata.name, ownerReferences: .metadata.ownerReferences }")

  info "StatefulSet list with pvc attached: ${statefulset_list}"
  for statefulset in ${statefulset_list};
  do
    local statefulset_name
    local claimtemplate_name
    local namespace
    local replica
    local ownerReferences
    statefulset_name=$(echo "${statefulset}"| jq -r ".name")
    claimtemplate_name=$(echo "${statefulset}"| jq -r ".claimName")
    namespace=$(echo "${statefulset}"| jq -r ".namespace")
    replica=$(echo "${statefulset}" | jq -r ".replicas")
    ownerReferences=$(echo "${statefulset}" | jq -c ".ownerReferences")

    local pvc_prefix upgrade_required=0
    pvc_prefix="${claimtemplate_name}-${statefulset_name}"

    for((i=0;i<"${replica}";i++))
    do
      local pvc_name
      pvc_name="${pvc_prefix}-${i}"

      # get pv for pvc
      get_pvc_resources_resp=""
      get_pvc_resources "${pvc_name}" "${namespace}"

      local pv_name
      pv_name=$(echo "${get_pvc_resources_resp}"| jq -r ".pv_name")

      get_current_pvc_engine "${pv_name}"
      if [[ "${LATEST_ENGINE_IMAGE}" == "${CURRENT_PVC_ENGINE}" ]]; then
        info "PVC volume already upgraded to new engine image ${CURRENT_PVC_ENGINE}"
        continue
      fi

      upgrade_required=1
      break
    done

    if [ "${upgrade_required}" == 0 ]; then
      continue
    fi

    info "Scaling down Statefulset ${statefulset_name} with ${replica} under namespace ${namespace}"
    # In case of rabbitmq and mongodb, we need to also scale down relevant operator
    if [[ ${statefulset_name} == "rabbitmq-server" && ${namespace} == "rabbitmq" ]]; then
      scale_down_deployment "rabbitmq-cluster-operator" "rabbitmq-system"
    elif [[ ${statefulset_name} == "mongodb-replica-set" && ${namespace} == "mongodb" ]]; then
      scale_down_deployment "mongodb-kubernetes-operator" "mongodb"
    fi
    scale_down_statefulset "${statefulset_name}" "${namespace}" "${ownerReferences}"

    for((i=0;i<"${replica}";i++))
    do
      local pvc_name
      pvc_name="${pvc_prefix}-${i}"

      # get pv for pvc
      get_pvc_resources_resp=""
      get_pvc_resources "${pvc_name}" "${namespace}"

      local pv_name
      pv_name=$(echo "${get_pvc_resources_resp}"| jq -r ".pv_name")

      get_current_pvc_engine "${pv_name}"
      if [[ "${LATEST_ENGINE_IMAGE}" == "${CURRENT_PVC_ENGINE}" ]]; then
        info "PVC volume already upgraded to new engine image ${CURRENT_PVC_ENGINE}"
        continue
      fi

      upgrade_pvc_engine "${pv_name}" "${CURRENT_PVC_ENGINE}"
      unset CURRENT_PVC_ENGINE

      if [[ "${UPGRADE_PVC_ENGINE_RESP}" -eq 0 ]]; then
        if [[ ${statefulset_name} == "rabbitmq-server" && ${namespace} == "rabbitmq" ]]; then
          scale_up_deployment "rabbitmq-cluster-operator" "rabbitmq-system" "1"
        elif [[ ${statefulset_name} == "mongodb-replica-set" && ${namespace} == "mongodb" ]]; then
          scale_up_deployment "mongodb-kubernetes-operator" "mongodb" "1"
        fi
        scale_up_statefulset "${statefulset_name}" "${namespace}" "${replica}" "${ownerReferences}"
        error "Upgrade failed for pvc ${pvc_name}, rollback statefulset ${statefulset_name}."
      fi
      unset UPGRADE_PVC_ENGINE_RESP
    info "Successfully upgraded engine image for pvc ${pvc_name}"
    done

    if [[ ${statefulset_name} == "rabbitmq-server" && ${namespace} == "rabbitmq" ]]; then
      scale_up_deployment "rabbitmq-cluster-operator" "rabbitmq-system" "1"
    elif [[ ${statefulset_name} == "mongodb-replica-set" && ${namespace} == "mongodb" ]]; then
      scale_up_deployment "mongodb-kubernetes-operator" "mongodb" "1"
    fi
    scale_up_statefulset "${statefulset_name}" "${namespace}" "${replica}" "${ownerReferences}"
    sleep 5
  done
}

function scale_up_statefulset() {
  local statefulset_name=$1
  local namespace=$2
  local replica=$3
  local ownerReferences=$4

  # Scale up statefulsets using PVCs
  info "Start Scale Up statefulset ${statefulset_name}..."

  # validate and scale up ownerreference
  scale_ownerreferences "${ownerReferences}" "${namespace}" "${replica}"

  info "Waiting to scale up statefulset..."

  local try=1
  local maxtry=15
  local success=0
  while (( try != maxtry )) ; do

    kubectl scale statefulset "${statefulset_name}" --replicas="${replica}" -n "${namespace}"
    kubectl get statefulset "${statefulset_name}" -n "${namespace}"

    scaleup=$(kubectl get statefulset "${statefulset_name}" -n "${namespace}"|grep "${replica}"/"${replica}") || true
    if ! { [ -n "${scaleup}" ] && [ "${scaleup}" != " " ]; }; then
      try=$((try+1))
      info "waiting for the statefulset ${statefulset_name} to scale up...${try}/${maxtry}"; sleep 30
    else
      info "Statefulset scaled up successfully."
      success=1
      break
    fi
  done

  if [ ${success} -eq 0 ]; then
    warn "Statefulset scaled up failed ${statefulset_name}."
  fi
}

function get_pvc_resources() {

  get_pvc_resources_resp=""

  local PVC_NAME=$1
  local PVC_NAMESPACE=$2

  # PV have one to one mapping with PVC
  PV_NAME=$(kubectl -n "${PVC_NAMESPACE}" get pvc "${PVC_NAME}" -o json|jq -r ".spec.volumeName")

  get_pvc_resources_resp="{\"pvc_name\": \"${PVC_NAME}\", \"pv_name\": \"${PV_NAME}\"}"
  echo "${get_pvc_resources_resp}"
}

########
# Validates longhorn backend endpoint is reachable
########
function validate_longhorn_reachable {
  local try=1
  local maxtry=31
  local success=0
  while (( try != maxtry )) ; do
    local backup_resp=""
    local resp_message=""
    backup_resp=$(curl --noproxy "*" "${LONGHORN_URL}/v1?") || true
    if { [ -n "${backup_resp}" ] && [ "${backup_resp}" != " " ]; }; then
      # verify if backupvolumes is exposed
      resp_message=$(echo "${backup_resp}"| grep "/v1/backupvolumes")
      if [[ -n "${resp_message}" && "${resp_message}" != " " ]]; then
        info "Longhorn Backend is Accessible"
        success=1
        break;
      fi
      info "waiting for longhorn backend to comeup ...${try}/${maxtry}";
    fi
    try=$((try+1))
    sleep 10
  done

  if [ ${success} -eq 0 ]; then
    error "Longhorn backend not accessible, error: ${backup_resp}."
  fi
}

function upgrade_longhorn() {
    # Manually upgrading engine image
    LONGHORN_COMPONENT_VERSION="v${COMPONENT_TARGET_VERSION}"
    # component version v1.1.2 -> longhorn version -> 1.1.2
    LONGHORN_VERSION="${COMPONENT_TARGET_VERSION:1}"

    # set longhorn url
    set_longhorn_url

    # check longhorn reachable
    validate_longhorn_reachable

    # get latest engine image
    get_latest_engine_image "${LONGHORN_COMPONENT_VERSION}"

    if [[ -z "${LATEST_ENGINE_IMAGE}" ]]; then
      error "No engine image found for version: ${LONGHORN_COMPONENT_VERSION}"
    fi
    info "Upgrading PVC volumes to version: ${LONGHORN_COMPONENT_VERSION} with engine image: ${LATEST_ENGINE_IMAGE}"

    # upgrade longhorn
    upgrade_engine_image_for_pvc_attached_to_deployments
    upgrade_engine_image_for_pvc_attached_to_statefulsets

    info "Upgrading Longhorn version ${LONGHORN_COMPONENT_VERSION} completed successfully."
}

function validate_pvc_ready_to_upgrade() {
  #ENABLE BELOW RETURN
  #return
  for _ in {1..10}; do
    pvc_unhealthy=$(kubectl -n longhorn-system get volumes.longhorn.io -o json| jq -r ".items[]| {name: .metadata.name, state: .status| select( .state != \"attached\" and  .state != \"detached\").state}")
    if [[ -z "${pvc_unhealthy}" ]]; then
      info "All pvc in healthy state for engineUpgrade"
      return
    fi
    info "Few pvc's are in unhealthy state, PVC List:  ${pvc_unhealthy}. Will retry.."
    sleep 60
  done
  error "Few pvc's are in unhealthy state, PVC List:  ${pvc_unhealthy}, please verify and then run longhorn upgrade."
}

function validate_longhorn_engine_version()  {
  local engine_name
  engine_name=$(kubectl -n longhorn-system get volumes.longhorn.io -o json|jq -r ".items[].spec| select ( .engineImage | contains(\"${COMPONENT_TARGET_VERSION}\" ) | not ).engineImage")
  if [[ -z "${engine_name}" ]]; then
    info "Component ${COMPONENT} already running at ${COMPONENT_TARGET_VERSION}. Skipping step"
    exit 0
  fi
}

verify_longhorn_engines_upgraded() {
  ready=0
  image_tag=$(kubectl get engineimages -n longhorn-system --sort-by=.metadata.creationTimestamp -o 'jsonpath={.items[-1].status.version}')

  for _ in {1..10}; do
    local volumes engines
    volumes=$(kubectl -n longhorn-system get volumes.longhorn.io -o json|jq -r ".items[].spec| select ( .engineImage | contains(\"${image_tag}\" ) | not ).engineImage")
    engines=$(kubectl -n longhorn-system get engines.longhorn.io -o json|jq -r ".items[].spec| select ( .engineImage | contains(\"${image_tag}\" ) | not ).engineImage")
    if [[ -z "${volumes}" && -z "${engines}" ]]; then
      ready=1 && break
    fi
    sleep 1
    volumes=$(kubectl -n longhorn-system get engines.longhorn.io -o json|jq -r ".items[].spec| select ( .engineImage | contains(\"${image_tag}\" ) | not ).volumeName")
    info "${volumes} are not upgraded yet"
  done
  [[ ${ready} -ne 1 ]] && warn "Longhorn volumes are not upgraded yet" && return 1
  info "Longhorn volumes are upgraded" && return 0
}

#MAIN
function main() {
    if [[ -z $1 ]]; then
       error "Missing target version"
    fi
    COMPONENT="longhorn"
    COMPONENT_TARGET_VERSION=$1
    local volumes engines
    image_tag=$(kubectl get engineimages -n longhorn-system --sort-by=.metadata.creationTimestamp -o 'jsonpath={.items[-1].status.version}')
    volumes=$(kubectl -n longhorn-system get volumes.longhorn.io -o json|jq -r ".items[].spec| select ( .engineImage | contains(\"${image_tag}\" ) | not ).engineImage")
    engines=$(kubectl -n longhorn-system get engines.longhorn.io -o json|jq -r ".items[].spec| select ( .engineImage | contains(\"${image_tag}\" ) | not ).engineImage")
    if [[ -z "${volumes}" && -z "${engines}" ]]; then
      info "Longhorn engine images are already upgraded"
      return
    fi

    # validate longhorn step
    validate_longhorn_engine_version

    # validate all pvc in health or detached state
    validate_pvc_ready_to_upgrade

    # longhorn upgrade
    upgrade_longhorn

#    verify_longhorn_engines_upgraded || error "Longhorn engine images are not upgraded"
}

# Pass additional arguments from upgrade path to main function.
main "${@:1}"