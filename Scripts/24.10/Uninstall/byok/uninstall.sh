#!/bin/bash
#
# uninstall.sh - Remove UiPath Automation Suite (BYOK) from a Kubernetes or
# OpenShift cluster. Works across Automation Suite versions (24.10, 25.10,
# 26.10, ...) because it discovers what to remove instead of hardcoding
# per-version component lists, using the same markers uipathctl itself sets:
#
#   * ArgoCD Applications carrying spec.info[] {name: InstalledBy, value: UiPath}
#   * Helm releases carrying the installedBy=UiPath marker
#     (in the release values or as a label on the helm release secret)
#
# Mirrors the semantics of `uipathctl manifest delete`:
#   1. ArgoCD Applications are deleted first, while ArgoCD is still running,
#      so the app controller cascade-deletes the deployed resources.
#      Applications stuck on resources-finalizer.argocd.argoproj.io are
#      escalated by removing their finalizers after a timeout.
#   2. Marked Helm releases are uninstalled afterwards, in reverse dependency
#      order (uipath products first, argocd/istio fabric last). Unmarked
#      releases - bring-your-own argocd / cert-manager / istio - are never
#      touched.
#   3. Leftover CRD instances and admission webhooks are cleaned up, then
#      namespaces are deleted; namespaces stuck in Terminating are
#      force-finalized.
#   4. Roles and rolebindings go last: in-cluster controllers (dapr
#      operator, argocd) still need their RBAC to process finalizers while
#      the namespaces terminate.
#
# NOTE: deliberately no `set -e` - every deletion is best-effort and reports
# its own failure; a single missing resource must not abort the uninstall.
set -uo pipefail

K8S_DISTRIBUTION="k8s"
DRY_RUN=false
VERBOSE=false
ASSUME_YES=false
EXCLUDED_COMPONENTS=()
CLUSTER_CONFIG_FILE=""
ISTIO_NAMESPACE="istio-system"
UIPATH_NAMESPACE="uipath"
ARGOCD_NAMESPACE="argocd"
WAIT_TIMEOUT=300
K8S_CMD="kubectl"
FAILURES=0
DELETE_UNMARKED_NS=false
# Components for which a UiPath-installed resource was discovered this run;
# leftover cleanup only touches these.
MANAGED_COMPONENTS=""

log() { echo "[uninstall] $*"; }
warn() {
  echo "[uninstall] WARNING: $*" >&2
  FAILURES=$((FAILURES + 1))
}
vlog() {
  [ "$VERBOSE" = true ] && echo "[uninstall] $*"
  return 0
}

# ---------------------------------------------------------------------------
# Static leftovers. ArgoCD applications and helm releases are discovered
# dynamically; these lists only cover resources that uninstalling the helm
# releases leaves behind (RBAC, CRD instances, webhooks, namespaces).
# Entry format: <type>:<name>[:<namespace>[,<namespace>...]]
# Types: role, rolebinding, priorityclass, crd (instances only), scc,
# webhooklabel, namespace. Roles/rolebindings without a namespace are
# cluster-scoped. Only explicit `namespace:` entries are deleted as namespaces.
# OLM operators (openshift-gitops, cert-manager) are cluster prerequisites
# installed by the cluster admin, not by uipathctl - never touched here.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034  # component variables are consumed via eval in delete_component_leftovers
function define_components {
  uipath="
    crd:components.dapr.io
    crd:configurations.dapr.io
    crd:subscriptions.dapr.io
    webhooklabel:app.kubernetes.io/part-of=dapr
    priorityclass:uipath-high-priority
    namespace:${UIPATH_NAMESPACE}
    "

  if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
    uipath+="
        role:limit-range-manager:${UIPATH_NAMESPACE}
        role:uipath-automationsuite-role:${UIPATH_NAMESPACE}
        rolebinding:limit-range-manager-binding:${UIPATH_NAMESPACE}
        rolebinding:uipath-automationsuite-rolebinding:${UIPATH_NAMESPACE}
        rolebinding:uipathadmin:${UIPATH_NAMESPACE}
        role:anyuid-role:${UIPATH_NAMESPACE}
        rolebinding:argocd-anyuid-binding:${UIPATH_NAMESPACE}
        role:dapr-creator:${UIPATH_NAMESPACE}
        role:manage-crds
        rolebinding:dapr-creator-binding:${UIPATH_NAMESPACE}
        rolebinding:gitops-dapr-creator-binding:${UIPATH_NAMESPACE}
        rolebinding:manage-crds-binding
        role:namespace-reader-clusterrole
        role:list-nodes-and-crd-clusterrole
        rolebinding:list-nodes-and-crd-rolebinding
        "
  else
    uipath+="
        role:dapr-role:${UIPATH_NAMESPACE}
        rolebinding:dapr-rolebinding:${UIPATH_NAMESPACE}
        role:uipath-role
        role:uipath-admin-role:default,${UIPATH_NAMESPACE}
        role:uipath-automationsuite-role:${UIPATH_NAMESPACE}
        role:uipath-viewer-role:${UIPATH_NAMESPACE}
        rolebinding:uipath-rolebinding
        rolebinding:uipath-admin-rolebinding:default,${UIPATH_NAMESPACE}
        rolebinding:uipath-automationsuite-rolebinding:${UIPATH_NAMESPACE}
        rolebinding:uipath-viewer-rolebinding:${UIPATH_NAMESPACE}
        rolebinding:uipathadmin:${UIPATH_NAMESPACE}
        role:namespace-reader-clusterrole
        role:list-nodes-and-crd-clusterrole
        role:storage-class-reader
        rolebinding:namespace-reader-rolebinding
        rolebinding:list-nodes-and-crd-rolebinding
        rolebinding:storage-class-reader-binding
        "
  fi

  authentication="
    role:keycloak-role:${UIPATH_NAMESPACE}
    rolebinding:keycloak-rolebinding:${UIPATH_NAMESPACE}
    "

  gatekeeper="
    webhooklabel:gatekeeper.sh/system=yes
    namespace:gatekeeper-system
    "

  falco="
    namespace:falco
    "

  if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
    cert_manager="
        role:argocd-cert-manager-role:${UIPATH_NAMESPACE}
        rolebinding:argocd-cert-manager-binding:${UIPATH_NAMESPACE}
        rolebinding:gitops-cert-manager-binding:${UIPATH_NAMESPACE}
        crd:certificates.cert-manager.io
        crd:issuers.cert-manager.io
        crd:clusterissuers.cert-manager.io
        "
  else
    cert_manager="
        role:cert-manager-role:cert-manager
        rolebinding:cert-manager-rolebinding:cert-manager
        crd:certificates.cert-manager.io
        crd:issuers.cert-manager.io
        crd:clusterissuers.cert-manager.io
        webhooklabel:app.kubernetes.io/instance=cert-manager
        namespace:cert-manager
        "
  fi

  if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
    shared_gitops="
        role:argo-secret-role:openshift-gitops
        role:uipath-application-manager:openshift-gitops
        rolebinding:secret-binding:openshift-gitops
        rolebinding:uipath-application-manager:openshift-gitops
        rolebinding:namespace-reader-rolebinding:openshift-gitops
        scc:anyuid
        "
  fi

  argocd="
    role:argo-secret-role:${ARGOCD_NAMESPACE}
    role:uipath-application-manager:${ARGOCD_NAMESPACE}
    rolebinding:secret-binding:${ARGOCD_NAMESPACE}
    rolebinding:namespace-reader-rolebinding:${ARGOCD_NAMESPACE}
    "

  # AppProject-based installs run in the shared, platform-owned
  # openshift-gitops namespace - clean up RBAC inside it but never queue the
  # namespace itself for deletion.
  case "$ARGOCD_NAMESPACE" in
  openshift-*) ;;
  *)
    argocd+="
        namespace:${ARGOCD_NAMESPACE}
        "
    ;;
  esac

  if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
    argocd+="
        rolebinding:uipath-application-manager:${ARGOCD_NAMESPACE}
        "
  else
    argocd+="
        rolebinding:uipath-application-manager-rolebinding:${ARGOCD_NAMESPACE}
        "
  fi

  istio="
    role:istio-system-automationsuite-role:${ISTIO_NAMESPACE}
    rolebinding:istio-system-automationsuite-rolebinding:${ISTIO_NAMESPACE}
    rolebinding:namespace-reader-rolebinding:${ISTIO_NAMESPACE}
    rolebinding:uipadmin-istio-system:${ISTIO_NAMESPACE}
    crd:virtualservices.networking.istio.io
    crd:gateways.networking.istio.io
    crd:destinationrules.networking.istio.io
    webhooklabel:istio.io/rev
    namespace:${ISTIO_NAMESPACE}
    "
}

# get_all_components lists components in deletion order: products first, then
# the fabric in reverse install order (cert-manager, argocd, istio last).
function get_all_components {
  local components="uipath"
  if [ "$K8S_DISTRIBUTION" != "openshift" ]; then
    components="$components authentication"
  fi
  components="$components falco gatekeeper cert_manager"
  if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
    components="$components shared_gitops"
  fi
  components="$components argocd istio"
  echo "$components"
}

function show_help {
  echo "Usage: $0 [DISTRIBUTION] [OPTIONS]"
  echo
  echo "DISTRIBUTION:"
  echo "  k8s        Use standard Kubernetes resources and commands (default)"
  echo "  openshift  Use OpenShift resources and commands"
  echo
  echo "OPTIONS:"
  echo "  -h, --help                         Display this help message and exit"
  echo "  -d, --dry-run                      Perform a dry run (no actual deletion)"
  echo "  -v, --verbose                      Show detailed information during execution"
  echo "  -y, --yes                          Do not ask for confirmation (for automation)"
  echo "  --excluded COMPONENT1,COMPONENT2   Components to exclude from deletion (comma-separated)"
  echo "  --clusterconfig FILE               Path to cluster configuration JSON file with exclude_components array"
  echo "  --istioNamespace NAMESPACE         Custom namespace for Istio components (default: istio-system)"
  echo "  --uipathNamespace NAMESPACE        Custom namespace for UiPath components (default: uipath)"
  echo "  --argocdNamespace NAMESPACE        Custom namespace for ArgoCD components (default: argocd)"
  echo "  --timeout SECONDS                  Seconds to wait for a deletion before escalating (default: 300)"
  echo "  --delete-unmarked-namespaces       Also delete namespaces without the uipath.com/created-by=uipathctl label"
  echo
  echo "Examples:"
  echo "  $0 k8s --excluded istio,argocd               # Keep istio and argocd, delete all others"
  echo "  $0 openshift --dry-run                       # Show what would be deleted"
  echo "  $0 k8s --clusterconfig cluster_config.json   # Read excluded components from JSON file"
  echo
  echo "Available components (in deletion order):"
  get_all_components | tr ' ' '\n' | sed 's/^/  - /'
  echo
}

function check_prerequisites {
  if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
    if ! command -v oc >/dev/null 2>&1; then
      echo "Error: oc (OpenShift CLI) is not installed or not in PATH"
      exit 1
    fi
    K8S_CMD="oc"
  else
    if ! command -v kubectl >/dev/null 2>&1; then
      echo "Error: kubectl is not installed or not in PATH"
      exit 1
    fi
    K8S_CMD="kubectl"
  fi

  local tool
  for tool in helm jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Error: $tool is not installed or not in PATH"
      exit 1
    fi
  done

  if [ -n "$CLUSTER_CONFIG_FILE" ] && [ ! -f "$CLUSTER_CONFIG_FILE" ]; then
    echo "Error: Cluster configuration file '$CLUSTER_CONFIG_FILE' not found"
    exit 1
  fi

  if ! $K8S_CMD version >/dev/null 2>&1; then
    echo "Error: cannot reach the cluster with $K8S_CMD; check your kubeconfig/context"
    exit 1
  fi
}

function read_excluded_from_json {
  local file="$1"
  [ -f "$file" ] || return 0
  jq -r '(.exclude_components // []) | join(",")' "$file" 2>/dev/null
}

function mark_component_managed {
  local component=$1
  [ -z "$component" ] && return 0
  case " $MANAGED_COMPONENTS " in
  *" $component "*) ;;
  *) MANAGED_COMPONENTS+=" $component" ;;
  esac
}

function is_component_managed {
  case " $MANAGED_COMPONENTS " in
  *" $1 "*) return 0 ;;
  esac
  return 1
}

function is_excluded {
  local component=$1 excluded
  for excluded in ${EXCLUDED_COMPONENTS[@]+"${EXCLUDED_COMPONENTS[@]}"}; do
    [ "$component" = "$excluded" ] && return 0
  done
  return 1
}

# argo_namespaces prints every namespace that may hold our Applications.
function argo_namespaces {
  echo "$ARGOCD_NAMESPACE"
  if [ "$K8S_DISTRIBUTION" = "openshift" ] && [ "$ARGOCD_NAMESPACE" != "openshift-gitops" ]; then
    echo "openshift-gitops"
  fi
}

# ---------------------------------------------------------------------------
# Discovery - the same markers uipathctl checks in IsApplicationManaged.
# ---------------------------------------------------------------------------

# discover_uipath_apps prints "<namespace> <name>" for every ArgoCD
# Application carrying the InstalledBy=UiPath info marker.
function discover_uipath_apps {
  local ns
  for ns in $(argo_namespaces); do
    $K8S_CMD get applications.argoproj.io -n "$ns" -o json 2>/dev/null |
      jq -r --arg ns "$ns" '.items[]?
                | select([.spec.info[]? | select(.name == "InstalledBy" and .value == "UiPath")] | length > 0)
                | "\($ns) \(.metadata.name)"'
  done
}

# helm_release_managed succeeds when the release carries the
# installedBy=UiPath marker, either in the release values (newer versions)
# or as a label on the helm release secret (older versions).
function helm_release_managed {
  local release=$1 namespace=$2

  if [ "$(helm get values "$release" -n "$namespace" -o json 2>/dev/null |
    jq -r '.installedBy // empty')" = "UiPath" ]; then
    return 0
  fi

  $K8S_CMD get secrets -n "$namespace" -l "owner=helm,name=$release" -o json 2>/dev/null |
    jq -e 'any(.items[]?; .metadata.labels.installedBy == "UiPath")' >/dev/null 2>&1
}

# release_rank orders helm uninstalls: uipath products first, then unknown
# namespaces, then the fabric bottom-up (cert-manager, argocd, istio last -
# within istio, config and gateways before istiod and base).
function release_rank {
  local namespace=$1 release=$2

  if [ "$namespace" = "$UIPATH_NAMESPACE" ]; then
    echo 10
  elif [ "$namespace" = "gatekeeper-system" ] || [ "$namespace" = "falco" ]; then
    echo 25
  elif [ "$namespace" = "cert-manager" ]; then
    echo 30
  elif [ "$namespace" = "$ARGOCD_NAMESPACE" ] || [ "$namespace" = "openshift-gitops" ]; then
    echo 40
  elif [ "$namespace" = "$ISTIO_NAMESPACE" ]; then
    case "$release" in
    istio-configure) echo 50 ;;
    gateway | istio-ingressgateway) echo 51 ;;
    istio | istiod) echo 52 ;;
    base | istio-base) echo 53 ;;
    *) echo 54 ;;
    esac
  else
    echo 20
  fi
}

# release_component maps a helm release to the component name used by
# --excluded, so exclusions also skip the dynamic uninstall phase.
function release_component {
  local namespace=$1 release=$2

  if [ "$release" = "keycloak" ]; then
    echo "authentication"
    return
  fi

  case "$namespace" in
  "$UIPATH_NAMESPACE") echo "uipath" ;;
  "$ISTIO_NAMESPACE") echo "istio" ;;
  "$ARGOCD_NAMESPACE" | openshift-gitops) echo "argocd" ;;
  cert-manager) echo "cert_manager" ;;
  gatekeeper-system) echo "gatekeeper" ;;
  falco) echo "falco" ;;
  *) echo "" ;;
  esac
}

# discover_uipath_releases prints "<rank> <namespace> <release>" for every
# helm release carrying the installedBy=UiPath marker, sorted in deletion
# order. Unmarked (bring-your-own) releases are skipped.
function discover_uipath_releases {
  local namespace release
  while read -r namespace release; do
    [ -z "$release" ] && continue
    if helm_release_managed "$release" "$namespace"; then
      echo "$(release_rank "$namespace" "$release") $namespace $release"
    else
      # stderr: this function's stdout is the discovered release list
      vlog "helm release $namespace/$release does not carry the installedBy=UiPath marker, skipping (bring-your-own)" >&2
    fi
  done < <(helm list -A -o json 2>/dev/null | jq -r '.[] | "\(.namespace) \(.name)"') | sort -n
}

# ---------------------------------------------------------------------------
# Deletion primitives.
# ---------------------------------------------------------------------------

function delete_argocd_app {
  local namespace=$1 app=$2

  if $DRY_RUN; then
    echo "DRY-RUN: Would delete ArgoCD application $namespace/$app"
    return 0
  fi

  log "Deleting ArgoCD application $namespace/$app"
  $K8S_CMD delete application.argoproj.io "$app" -n "$namespace" \
    --ignore-not-found=true --wait=false >/dev/null || warn "cannot delete application $namespace/$app"

  # Give the ArgoCD controller a chance to cascade-delete the app's
  # resources; if it is stuck on its finalizer, strip the finalizer.
  if ! $K8S_CMD wait --for=delete "application.argoproj.io/$app" -n "$namespace" \
    --timeout="${WAIT_TIMEOUT}s" >/dev/null 2>&1; then
    if $K8S_CMD get application.argoproj.io "$app" -n "$namespace" >/dev/null 2>&1; then
      log "Application $namespace/$app is stuck; removing finalizers"
      $K8S_CMD patch application.argoproj.io "$app" -n "$namespace" --type=merge \
        -p '{"metadata":{"finalizers":null}}' >/dev/null ||
        warn "cannot remove finalizers from application $namespace/$app"
    fi
  fi
}

function delete_helm_release {
  local namespace=$1 release=$2

  if $DRY_RUN; then
    echo "DRY-RUN: Would uninstall helm release $namespace/$release"
    return 0
  fi

  log "Uninstalling helm release $namespace/$release"
  helm uninstall "$release" -n "$namespace" --timeout "${WAIT_TIMEOUT}s" >/dev/null ||
    warn "cannot uninstall helm release $namespace/$release"
}

function delete_namespaced_or_cluster {
  local kind=$1 clusterkind=$2 name=$3 namespace=$4

  if [ -n "$namespace" ]; then
    if ! $K8S_CMD get namespace "$namespace" >/dev/null 2>&1; then
      vlog "namespace $namespace not found, skipping $kind $name"
      return 0
    fi
    if $DRY_RUN; then
      echo "DRY-RUN: Would delete $kind $namespace/$name"
    else
      vlog "Deleting $kind $namespace/$name"
      $K8S_CMD delete "$kind" "$name" -n "$namespace" --ignore-not-found=true >/dev/null ||
        warn "cannot delete $kind $namespace/$name"
    fi
  else
    if $DRY_RUN; then
      echo "DRY-RUN: Would delete $clusterkind $name"
    else
      vlog "Deleting $clusterkind $name"
      $K8S_CMD delete "$clusterkind" "$name" --ignore-not-found=true >/dev/null ||
        warn "cannot delete $clusterkind $name"
    fi
  fi
}

function delete_crd_instances {
  local crd=$1

  $K8S_CMD get crd "$crd" >/dev/null 2>&1 || {
    vlog "CRD $crd not found, skipping"
    return 0
  }

  if $DRY_RUN; then
    echo "DRY-RUN: Would delete all instances of CRD $crd"
    return 0
  fi

  log "Deleting all instances of CRD $crd"
  local scope
  scope=$($K8S_CMD get crd "$crd" -o jsonpath='{.spec.scope}' 2>/dev/null)
  # --wait=false: instances stuck on finalizers must not hang the script;
  # namespace force-finalization cleans them up at the end.
  if [ "$scope" = "Namespaced" ]; then
    $K8S_CMD delete "$crd" --all --all-namespaces --ignore-not-found=true --wait=false >/dev/null ||
      warn "cannot delete instances of $crd"
  else
    $K8S_CMD delete "$crd" --all --ignore-not-found=true --wait=false >/dev/null ||
      warn "cannot delete instances of $crd"
  fi
}

# delete_webhooks_by_label removes leftover admission webhooks so that
# namespace teardown is not blocked by webhooks pointing at dead services.
function delete_webhooks_by_label {
  local selector=$1

  if $DRY_RUN; then
    echo "DRY-RUN: Would delete mutating/validating webhooks with label $selector"
    return 0
  fi

  vlog "Deleting admission webhooks with label $selector"
  $K8S_CMD delete mutatingwebhookconfigurations,validatingwebhookconfigurations \
    -l "$selector" --ignore-not-found=true >/dev/null ||
    warn "cannot delete webhooks with label $selector"
}

function delete_scc {
  local scc=$1

  if $DRY_RUN; then
    echo "DRY-RUN: Would delete security context constraint $scc"
    return 0
  fi

  log "Deleting security context constraint $scc"
  $K8S_CMD delete scc "$scc" --ignore-not-found=true >/dev/null || warn "cannot delete scc $scc"
}

function delete_namespace {
  local namespace=$1

  # Never delete cluster-critical namespaces, whatever the configuration
  # says. A logged skip, not a failure: shared platform namespaces (e.g.
  # openshift-gitops) legitimately reach this point on AppProject installs.
  case "$namespace" in
  default | kube-system | kube-public | kube-node-lease | openshift-*)
    log "Skipping protected namespace $namespace"
    return 0
    ;;
  esac

  $K8S_CMD get namespace "$namespace" >/dev/null 2>&1 || {
    vlog "namespace $namespace not found, skipping"
    return 0
  }

  # Only delete namespaces uipathctl itself created (marked by
  # uipath.com/created-by=uipathctl); customer-precreated namespaces are
  # left in place. Pre-marker uipathctl versions and full test teardowns
  # can force this with --delete-unmarked-namespaces.
  if ! $DELETE_UNMARKED_NS; then
    local created_by
    created_by=$($K8S_CMD get namespace "$namespace" -o json 2>/dev/null |
      jq -r '.metadata.labels["uipath.com/created-by"] // empty')
    if [ "$created_by" != "uipathctl" ]; then
      log "Namespace $namespace was not created by uipathctl; leaving it in place (use --delete-unmarked-namespaces to remove)"
      return 0
    fi
  fi

  if $DRY_RUN; then
    echo "DRY-RUN: Would delete namespace $namespace"
    return 0
  fi

  log "Deleting namespace $namespace"
  $K8S_CMD delete namespace "$namespace" --ignore-not-found=true --wait=false >/dev/null ||
    warn "cannot delete namespace $namespace"

  if $K8S_CMD wait --for=delete "namespace/$namespace" --timeout="${WAIT_TIMEOUT}s" >/dev/null 2>&1; then
    return 0
  fi
  $K8S_CMD get namespace "$namespace" >/dev/null 2>&1 || return 0

  log "Namespace $namespace is stuck in Terminating; force-finalizing"
  $K8S_CMD get namespace "$namespace" -o json |
    jq 'del(.spec.finalizers)' |
    $K8S_CMD replace --raw "/api/v1/namespaces/$namespace/finalize" -f - >/dev/null ||
    warn "cannot force-finalize namespace $namespace"
}

# ---------------------------------------------------------------------------
# Phases.
# ---------------------------------------------------------------------------

function delete_applications {
  if is_excluded uipath; then
    log "Component uipath is excluded; keeping ArgoCD applications"
    return 0
  fi

  local apps namespace app
  apps=$(discover_uipath_apps)
  if [ -z "$apps" ]; then
    log "No UiPath-managed ArgoCD applications found"
    return 0
  fi

  mark_component_managed uipath
  log "UiPath-managed ArgoCD applications: $(echo "$apps" | awk '{printf "%s/%s ", $1, $2}')"
  while read -r namespace app; do
    [ -z "$app" ] && continue
    delete_argocd_app "$namespace" "$app"
  done <<<"$apps"
}

function delete_helm_releases {
  local releases _ namespace release component
  releases=$(discover_uipath_releases)
  if [ -z "$releases" ]; then
    log "No UiPath-managed helm releases found"
    return 0
  fi

  log "UiPath-managed helm releases (in deletion order): $(echo "$releases" | awk '{printf "%s/%s ", $2, $3}')"
  while read -r _ namespace release; do
    [ -z "$release" ] && continue
    component=$(release_component "$namespace" "$release")
    mark_component_managed "$component"
    if [ -n "$component" ] && is_excluded "$component"; then
      log "Keeping helm release $namespace/$release (component $component is excluded)"
      continue
    fi
    delete_helm_release "$namespace" "$release"
  done <<<"$releases"
}

# delete_component_leftovers cleans up one component's static leftovers.
# mode "resources": CRD instances, priority classes, SCCs, webhooks and
# namespaces. mode "rbac": roles and rolebindings only - deleted in a final
# pass AFTER all namespaces, because in-cluster controllers (dapr operator,
# argocd) still need their RBAC to process finalizers while namespaces
# terminate. Namespaced RBAC in deleted namespaces is gone by then anyway;
# this pass sweeps the cluster-scoped and surviving-namespace leftovers.
function delete_component_leftovers {
  local component_name=$1 mode=$2

  local component_def
  eval "component_def=\"\${$component_name:-}\""
  [ -z "$component_def" ] && return 0

  local crds="" webhook_selectors="" roles="" rolebindings=""
  local priority_classes="" sccs="" namespaces=""

  local line type resource
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue

    type=${line%%:*}
    resource=${line#*:}

    case "$type" in
    crd) crds+=" $resource" ;;
    webhooklabel) webhook_selectors+=" $resource" ;;
    role) roles+=" $resource" ;;
    rolebinding) rolebindings+=" $resource" ;;
    priorityclass) priority_classes+=" $resource" ;;
    scc) sccs+=" $resource" ;;
    namespace) namespaces+=" $resource" ;;
    *) warn "unknown resource type '$type' in component $component_name" ;;
    esac
  done <<<"$component_def"

  local item name ns
  if [ "$mode" = "rbac" ]; then
    for item in $rolebindings; do
      name=${item%%:*}
      if [ "$item" = "$name" ]; then
        delete_namespaced_or_cluster rolebinding clusterrolebinding "$name" ""
      else
        for ns in $(echo "${item#*:}" | tr ',' ' '); do
          delete_namespaced_or_cluster rolebinding clusterrolebinding "$name" "$ns"
        done
      fi
    done

    for item in $roles; do
      name=${item%%:*}
      if [ "$item" = "$name" ]; then
        delete_namespaced_or_cluster role clusterrole "$name" ""
      else
        for ns in $(echo "${item#*:}" | tr ',' ' '); do
          delete_namespaced_or_cluster role clusterrole "$name" "$ns"
        done
      fi
    done

    return 0
  fi

  for item in $crds; do
    delete_crd_instances "$item"
  done

  for item in $priority_classes; do
    delete_namespaced_or_cluster priorityclass priorityclass "$item" ""
  done

  if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
    for item in $sccs; do
      delete_scc "$item"
    done
  fi

  for item in $webhook_selectors; do
    delete_webhooks_by_label "$item"
  done

  for item in $namespaces; do
    delete_namespace "$item"
  done
}

function main {
  if [ $# -gt 0 ] && [ "${1:0:1}" != "-" ]; then
    K8S_DISTRIBUTION=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    shift

    if [ "$K8S_DISTRIBUTION" != "k8s" ] && [ "$K8S_DISTRIBUTION" != "openshift" ]; then
      echo "Error: Unrecognized distribution '$K8S_DISTRIBUTION'. Use 'k8s' or 'openshift'."
      echo
      show_help
      exit 1
    fi
  fi

  local excluded_arg=""

  while [ $# -gt 0 ]; do
    case "$1" in
    -h | --help)
      show_help
      exit 0
      ;;
    -d | --dry-run)
      DRY_RUN=true
      shift
      ;;
    -v | --verbose)
      VERBOSE=true
      shift
      ;;
    -y | --yes)
      ASSUME_YES=true
      shift
      ;;
    --excluded)
      excluded_arg="$2"
      shift 2
      ;;
    --clusterconfig)
      CLUSTER_CONFIG_FILE="$2"
      shift 2
      ;;
    --istioNamespace)
      ISTIO_NAMESPACE="$2"
      shift 2
      ;;
    --uipathNamespace)
      UIPATH_NAMESPACE="$2"
      shift 2
      ;;
    --argocdNamespace)
      ARGOCD_NAMESPACE="$2"
      shift 2
      ;;
    --timeout)
      WAIT_TIMEOUT="$2"
      shift 2
      ;;
    --delete-unmarked-namespaces)
      DELETE_UNMARKED_NS=true
      shift
      ;;
    *)
      echo "Error: Unknown option: $1"
      show_help
      exit 1
      ;;
    esac
  done

  check_prerequisites

  if [ -n "$excluded_arg" ]; then
    IFS=',' read -r -a CLI_EXCLUDED <<<"$excluded_arg"
    EXCLUDED_COMPONENTS+=("${CLI_EXCLUDED[@]}")
  fi

  if [ -n "$CLUSTER_CONFIG_FILE" ]; then
    local excluded_from_json
    excluded_from_json=$(read_excluded_from_json "$CLUSTER_CONFIG_FILE")
    if [ -n "$excluded_from_json" ]; then
      IFS=',' read -r -a JSON_EXCLUDED <<<"$excluded_from_json"
      EXCLUDED_COMPONENTS+=("${JSON_EXCLUDED[@]}")
    fi
  fi

  define_components

  local all_components comp found available
  all_components=$(get_all_components)
  read -r -a all_components_array <<<"$all_components"

  for comp in ${EXCLUDED_COMPONENTS[@]+"${EXCLUDED_COMPONENTS[@]}"}; do
    found=false
    for available in "${all_components_array[@]}"; do
      [ "$comp" = "$available" ] && {
        found=true
        break
      }
    done
    [ "$found" = false ] && echo "Warning: Component '$comp' is not recognized and will be ignored."
  done

  if [ ${#EXCLUDED_COMPONENTS[@]} -eq 0 ]; then
    log "No components excluded; everything installed by uipathctl will be deleted."
  else
    log "Components to keep: ${EXCLUDED_COMPONENTS[*]}"
  fi

  if ! $DRY_RUN && ! $ASSUME_YES; then
    echo
    read -r -p "This will PERMANENTLY delete the UiPath Automation Suite components from the current cluster. Continue? [y/N] " answer
    case "$answer" in
    y | Y | yes | YES) ;;
    *)
      echo "Aborted."
      exit 0
      ;;
    esac
  fi

  echo
  log "=== Phase 1/4: ArgoCD applications ==="
  delete_applications

  echo
  log "=== Phase 2/4: Helm releases ==="
  delete_helm_releases

  # shared_gitops holds the RBAC uipathctl creates in openshift-gitops for
  # its applications, so it is managed whenever the uipath component is.
  if [ "$K8S_DISTRIBUTION" = "openshift" ] && is_component_managed uipath; then
    mark_component_managed shared_gitops
  fi

  echo
  log "=== Phase 3/4: leftovers and namespaces ==="
  for comp in "${all_components_array[@]}"; do
    if is_excluded "$comp"; then
      log "Skipping leftovers of excluded component $comp"
      continue
    fi
    # Nothing uipathctl-installed was discovered for this component
    # (bring-your-own or already removed) - leave its resources alone.
    if ! is_component_managed "$comp"; then
      log "Skipping leftovers of component $comp (no uipathctl-installed resources discovered)"
      continue
    fi
    log "Cleaning up leftovers of component $comp"
    delete_component_leftovers "$comp" resources
  done

  # RBAC goes last: in-cluster controllers still need their roles and
  # rolebindings to process finalizers while the namespaces terminate.
  echo
  log "=== Phase 4/4: RBAC cleanup ==="
  for comp in "${all_components_array[@]}"; do
    is_excluded "$comp" && continue
    is_component_managed "$comp" || continue
    delete_component_leftovers "$comp" rbac
  done

  echo
  if $DRY_RUN; then
    log "Dry run completed. No changes were made."
  elif [ "$FAILURES" -gt 0 ]; then
    log "Uninstall finished with $FAILURES warning(s); review the output above."
    exit 1
  else
    log "Automation Suite has been uninstalled."
  fi
}

main "$@"
