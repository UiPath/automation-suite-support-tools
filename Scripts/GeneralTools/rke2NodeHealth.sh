#!/bin/bash

export PATH="$PATH:/var/lib/rancher/rke2/bin:/usr/local/bin"

[[ -f "/var/lib/rancher/rke2/agent/kubelet.kubeconfig" ]] && export KUBECONFIG="/var/lib/rancher/rke2/agent/kubelet.kubeconfig"
[[ -f "/etc/rancher/rke2/rke2.yaml" ]] && export KUBECONFIG="/etc/rancher/rke2/rke2.yaml"

LOG_FILE=${NODE_HEALTH_SCRIPT_LOG_FILE:-"/var/log/node-health-script.log"}

# Common for agent and server nodes
RKE2_SERVICE_IS_ACTIVE_TIMEOUT_SECONDS="${RKE2_SERVICE_IS_ACTIVE_TIMEOUT_SECONDS:-100}"
RKE2_SERVICE_IS_ACTIVE_RESTART_COUNT="${RKE2_SERVICE_IS_ACTIVE_RESTART_COUNT:-2}"
KUBE_NODE_READY_TIMEOUT_SECONDS="${KUBE_NODE_READY_TIMEOUT_SECONDS:-60}"

# Server specific
KUBE_ALL_NODES_READY_TIMEOUT_SECONDS="${KUBE_ALL_NODES_READY_TIMEOUT_SECONDS:-100}"

readonly RKE2_SERVER_SERVICE_NAME="rke2-server.service"
readonly RKE2_AGENT_SERVICE_NAME="rke2-agent.service"

RED='\033[0;31m'
NC='\033[0m'

function get_local_k8s_node_name(){
  xargs -0 < "/proc/$(pgrep kubelet)/cmdline" | tr ' ' '\n' | grep '\-\-hostname\-override' | cut -d'=' -f2
}

function discover_rke2_service_name() {
  local service_name="${RKE2_AGENT_SERVICE_NAME}"
  grep -q 'kube-apiserver-arg' /etc/rancher/rke2/config.yaml && service_name="${RKE2_SERVER_SERVICE_NAME}"
  echo "${service_name}"
}

function get_os_start_time(){
  date -d "$(uptime -s)" +%s
}

function get_rke2_service_start_time() {
  local service_name="$1"

  date -d"$(systemctl show -p ExecMainStartTimestamp --value "${service_name}")" "+%s"
}

function log_to_file() {
  local level="$1"
  shift
  local log="$*"
  local color

  case "$level" in
    ERROR)
      color="$RED"
    ;;
  esac

  local datetime=$(date +'%Y-%m-%dT%H:%M:%S%z')

  touch "${LOG_FILE}"

  echo -e "${color}[${level}] [${datetime}]: $*${NC}" | tee -a "${LOG_FILE}"
}

function is_service_present() {
  local name="$1"
  local return_code=1

  systemctl cat "${name}" >> /dev/null && return_code=0

  return "${return_code}"
}

function get_service_status() {
  local name="$1"

  systemctl is-active "${name}"
}

function is_rke2_service_timeout() {
  local name="$1"
  local timeout_seconds="$2"
  local service_elapsed_time
  local timed_out=1

  start_time="$(get_rke2_service_start_time "$name")"
  current_time="$(date "+%s")"

  service_elapsed_time="$(( current_time - start_time ))"
  if [[ "${service_elapsed_time}" -gt "$timeout_seconds" ]]; then
    timed_out=0
  fi

  return "${timed_out}"
}

function is_rke2_service_restart_exhausted() {
  local name="$1"
  local allowed_restarts="$2"
  local initial_restart="$3"

  local exhausted=1

  current_restarts="$(get_rke2_service_restart_count "$name")"

  delta_restarts="$(( current_restarts - initial_restart ))"
  if [[ "${delta_restarts}" -gt "${allowed_restarts}" ]]; then
    exhausted=0
  fi

  return "${exhausted}"
}

function get_rke2_service_restart_count() {
  local name="$1"

  systemctl show -p NRestarts --value "$name"
}

function validate_istio_ingress_gateway_endpoint_connectivity() {
  local return_code=0
  local expected_code=404
  local endpoint_found=false
  local istio_ingress_gw_http_target_port

  istio_ingress_gw_http_target_port="$(kubectl -n istio-system get svc  istio-ingressgateway -o json | jq -r '.spec.ports[] | select(.port == 80).targetPort')"

  for i in $(kubectl -n istio-system get endpoints istio-ingressgateway  -o json | jq -r '.subsets[].addresses[] | .nodeName + "=" + .ip'); do
    endpoint_found=true
    nodeName="$(echo "${i}" | cut -d'=' -f1)"
    podIP="$(echo "${i}" | cut -d'=' -f2)"
    http_code="$(curl -m 10 -s -o /dev/null -w "%{http_code}" "${podIP}:${istio_ingress_gw_http_target_port}")"
    if [[ "$http_code" -ne 404 ]]; then
      return_code=1
      log_to_file "ERROR" "Unexpected http code ${http_code} received for istio ingress-gateway endpoint IP ${podIP} on node ${nodeName}"
      continue
    fi

    log_to_file "INFO" "Successfully connected to istio ingress-gateway endpoint(${podIP}) on node ${nodeName}"
  done

  [[ "$endpoint_found" == "false" ]] && {
    log_to_file "ERROR" "No endpoints discovered to validate connectivity"
    return 1
  }

  return "${return_code}"
}


function is_node_ready() {
  local node_name="$1"

  [[ "$(kubectl get node "${node_name}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == "True" ]]
}

function all_nodes_ready() {
  local ret_code=0

  kubectl get node | grep -q 'NotReady' && ret_code=1

  return "${ret_code}"
}

function wait_until_current_node_ready(){
  local timeout="$1"
  local start_time="$(date "+%s")"
  local node_name

  while true; do
    node_name="$(get_local_k8s_node_name)"

    if [[ -n "${node_name}" && is_node_ready ]]; then
      log_to_file "INFO" "kubernetes node ${node_name} is ready"
      return 0
    fi

    log_to_file "INFO" "Waiting for kubernetes node ${node_name} to become ready"

    current_time="$(date "+%s")"
    diff=$(( current_time - start_time ))
    if [[ "$diff" -gt "$timeout" ]]; then
      log_to_file "ERROR" "Timeout waiting for kubernetes node ${node_name} to become ready"
      return 1
    fi

    sleep 2
  done
}

function wait_until_all_nodes_ready() {
  local timeout="$1"
  local start_time="$(date "+%s")"

  while true; do
    kubectl get node --no-headers  | grep ' Ready' -v || {
      log_to_file "INFO" "All nodes are ready"
      return 0
    }

    current_time="$(date "+%s")"
    diff=$(( current_time - start_time ))
    if [[ "$diff" -gt "$timeout" ]]; then
      log_to_file "ERROR" "Timeout waiting for all kubernetes nodes to become ready"
      return 1
    fi

    sleep 5
  done
}

function validate_cilium_connectivity(){
  local return_code=0

  for i in $(kubectl get ciliumnodes.cilium.io -o json | jq -r '.items[] | .metadata.name + "=" +  (.spec.health | .[])'); do
    node_name="$(echo "$i" | cut -d'=' -f1)"
    ip="$(echo "$i" | cut -d'=' -f2)"
    http_code=$(curl -m 10 -s -o /dev/null -w "%{http_code}" "${ip}:4240/hello")
    [[ "$http_code" -ne 200 ]] && {
      return_code=1
      log_to_file "ERROR" "Unexpected http code ${http_code} received for cilium endpoint IP ${ip} on node ${node_name}"
      continue
    }

    log_to_file "INFO" "Successfully connected to cilium endpoint(${ip}) on node ${node_name}"
  done

  return "${return_code}"
}


function main() {
  local initial_restart_count

  rke2_service_name=$(discover_rke2_service_name)


  log_to_file "INFO" "Discovered RKE2 service name: ${rke2_service_name}"

  if ! is_service_present "${rke2_service_name}"; then
    log_to_file "ERROR" "Unable to find discovered RKE2 service ${rke2_service_name}"
    exit 1
  fi

  log_to_file "INFO" "Waiting for discovered RKE2 service ${rke2_service_name} to become healthy"

  while [[ "$(get_service_status "${rke2_service_name}")" != "active" ]]; do
    if is_rke2_service_timeout "${rke2_service_name}" "${RKE2_SERVICE_IS_ACTIVE_TIMEOUT_SECONDS}"; then
      log_to_file "ERROR" "Timeout: unable to start RKE2 service ${rke2_service_name}"
      exit 1
    fi

    [[ -z "$initial_restart_count" ]] && initial_restart_count="$(get_rke2_service_restart_count "${rke2_service_name}")"

    if is_rke2_service_restart_exhausted "${rke2_service_name}" "${RKE2_SERVICE_IS_ACTIVE_RESTART_COUNT}" "${initial_restart_count}"; then
      log_to_file "ERROR" "Timeout: unable to start RKE2 service ${rke2_service_name} after multiple retries"
      exit 1
    fi

    sleep 5
  done

  log_to_file "INFO" "RKE2 service ${rke2_service_name} is healthy"

  wait_until_current_node_ready "${KUBE_NODE_READY_TIMEOUT_SECONDS}" || exit 1

  validate_istio_ingress_gateway_endpoint_connectivity || exit 1

  if [[ "${rke2_service_name}" == "${RKE2_SERVER_SERVICE_NAME}" ]]; then
    log_to_file "INFO" "Waiting for all kubernetes nodes to become healthy"

    wait_until_all_nodes_ready "${KUBE_ALL_NODES_READY_TIMEOUT_SECONDS}" || exit 1

    validate_cilium_connectivity || exit 1
  fi
}

function help() {
 echo "Run this script to validate RKE2 node health"
 echo "The script does not expect any argument to run the validation checks"
}

if [[ $# -ne 0 ]]; then
  help
  exit 0
fi

main
