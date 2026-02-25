#!/bin/bash

K8S_DISTRIBUTION="k8s"
DRY_RUN=false
VERBOSE=false
EXCLUDED_COMPONENTS=()
CLUSTER_CONFIG_FILE=""
ISTIO_NAMESPACE="istio-system"
UIPATH_NAMESPACE="uipath"
ARGOCD_NAMESPACE="argocd"
ARGOCD_SHARED=false


# shellcheck disable=SC2034  # Variables are used via eval in delete_component
function define_components {
    # Istio: On OpenShift, customer provides service mesh - only clean up our roles/rolebindings
    if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
        istio="
        role:istio-system-automationsuite-role:${ISTIO_NAMESPACE}
        rolebinding:istio-system-automationsuite-rolebinding:${ISTIO_NAMESPACE}
        rolebinding:namespace-reader-rolebinding:${ISTIO_NAMESPACE}
        rolebinding:uipadmin-istio-system:${ISTIO_NAMESPACE}
        "
    else
        istio="
        helm:istio-base:${ISTIO_NAMESPACE}
        helm:base:${ISTIO_NAMESPACE}
        helm:istio:${ISTIO_NAMESPACE}
        helm:istio-ingressgateway:${ISTIO_NAMESPACE}
        helm:gateway:${ISTIO_NAMESPACE}
        role:istio-system-automationsuite-role:${ISTIO_NAMESPACE}
        rolebinding:istio-system-automationsuite-rolebinding:${ISTIO_NAMESPACE}
        rolebinding:namespace-reader-rolebinding:${ISTIO_NAMESPACE}
        rolebinding:uipadmin-istio-system:${ISTIO_NAMESPACE}
        namespace:${ISTIO_NAMESPACE}
        crd:virtualservices.networking.istio.io
        crd:gateways.networking.istio.io
        crd:destinationrules.networking.istio.io
        "
    fi

    istio_configure="
      helm:istio-configure:${ISTIO_NAMESPACE}
    "

    # ArgoCD: On OpenShift, customer provides ArgoCD operator - only clean up our roles/rolebindings
    if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
        argocd="
        role:argo-secret-role:${ARGOCD_NAMESPACE}
        role:uipath-application-manager:${ARGOCD_NAMESPACE}
        rolebinding:secret-binding:${ARGOCD_NAMESPACE}
        rolebinding:uipath-application-manager:${ARGOCD_NAMESPACE}
        rolebinding:namespace-reader-rolebinding:${ARGOCD_NAMESPACE}
        "
    else
        argocd="
        role:argo-secret-role:${ARGOCD_NAMESPACE}
        role:uipath-application-manager:${ARGOCD_NAMESPACE}
        rolebinding:secret-binding:${ARGOCD_NAMESPACE}
        namespace:${ARGOCD_NAMESPACE}
        rolebinding:uipath-application-manager-rolebinding:${ARGOCD_NAMESPACE}
        rolebinding:namespace-reader-rolebinding:${ARGOCD_NAMESPACE}
        "
    fi

    if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
        shared_gitops="
        role:uipath-application-manager:openshift-gitops
        rolebinding:uipath-application-manager:openshift-gitops
        "
    fi

    uipath="
    helm:uipath-orchestrator:${UIPATH_NAMESPACE}
    helm:uipath-identity-service:${UIPATH_NAMESPACE}
    helm:uipath-automation-suite:${UIPATH_NAMESPACE}
    namespace:${UIPATH_NAMESPACE}
    argocd:dapr
    argocd:actioncenter
    argocd:aicenter
    argocd:aievents
    argocd:aimetering
    argocd:airflow
    argocd:aistorage
    argocd:asrobots
    argocd:auth
    argocd:automationhub
    argocd:automationops
    argocd:ba
    argocd:datapipeline-api
    argocd:dataservice
    argocd:documentunderstanding
    argocd:insights
    argocd:integrationservices
    argocd:notificationservice
    argocd:orchestrator
    argocd:platform
    argocd:processmining
    argocd:pushgateway
    argocd:reloader
    argocd:robotube
    argocd:sfcore
    argocd:studioweb
    argocd:taskmining
    argocd:testmanager
    argocd:webhook
    priorityclass:uipath-high-priority
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
        crd:components.dapr.io
        crd:configurations.dapr.io
        crd:subscriptions.dapr.io
        role:namespace-reader-clusterrole
        role:list-nodes-and-crd-clusterrole
        rolebinding:list-nodes-and-crd-rolebinding
        "
    else
        uipath+="
        role:uipath-role
        role:uipath-admin-role:default,${UIPATH_NAMESPACE}
        role:uipath-automationsuite-role:${UIPATH_NAMESPACE}
        role:uipath-viewer-role:${UIPATH_NAMESPACE}
        rolebinding:uipath-rolebinding
        rolebinding:uipath-admin-rolebinding:default,${UIPATH_NAMESPACE}
        rolebinding:uipath-automationsuite-rolebinding:${UIPATH_NAMESPACE}
        rolebinding:uipath-viewer-rolebinding:${UIPATH_NAMESPACE}
        rolebinding:uipathadmin:${UIPATH_NAMESPACE}
        helm:dapr:${UIPATH_NAMESPACE}
        role:dapr-role:${UIPATH_NAMESPACE}
        rolebinding:dapr-rolebinding:${UIPATH_NAMESPACE}
        argocd:dapr
        crd:components.dapr.io
        crd:configurations.dapr.io
        crd:subscriptions.dapr.io
        role:namespace-reader-clusterrole
        role:list-nodes-and-crd-clusterrole
        role:storage-class-reader
        rolebinding:namespace-reader-rolebinding
        rolebinding:list-nodes-and-crd-rolebinding
        rolebinding:storage-class-reader-binding
        "
    fi

    # Cert-manager: On OpenShift, customer provides cert-manager operator - only clean up our roles/rolebindings
    if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
        cert_manager="
        role:argocd-cert-manager-role:${UIPATH_NAMESPACE}
        rolebinding:argocd-cert-manager-binding:${UIPATH_NAMESPACE}
        rolebinding:gitops-cert-manager-binding:${UIPATH_NAMESPACE}
        "
    else
        cert_manager="
        helm:cert-manager:cert-manager
        role:cert-manager-role:cert-manager
        rolebinding:cert-manager-rolebinding:cert-manager
        namespace:cert-manager
        crd:certificates.cert-manager.io
        crd:issuers.cert-manager.io
        crd:clusterissuers.cert-manager.io
        "
    fi

    # Keycloak: Only on k8s (EKS/AKS), not on OpenShift
    if [ "$K8S_DISTRIBUTION" != "openshift" ]; then
        authentication="
        helm:keycloak:${UIPATH_NAMESPACE}
        role:keycloak-role:${UIPATH_NAMESPACE}
        rolebinding:keycloak-rolebinding:${UIPATH_NAMESPACE}
        "
    fi

    network_policies="
    argocd:network-policies
    "

    # Gatekeeper: Only on k8s (EKS/AKS), not installed by uipathctl on OpenShift
    if [ "$K8S_DISTRIBUTION" != "openshift" ]; then
        gatekeeper="
        helm:gatekeeper:gatekeeper-system
        "
    fi
}


function show_help {
    echo "Usage: $0 [DISTRIBUTION] [OPTIONS]"
    echo
    echo "DISTRIBUTION:"
    echo "  k8s     Use standard Kubernetes resources and commands (default)"
    echo "  openshift      Use OpenShift resources and commands"
    echo
    echo "OPTIONS:"
    echo "  -h, --help                         Display this help message and exit"
    echo "  -d, --dry-run                      Perform a dry run (no actual deletion)"
    echo "  -v, --verbose                      Show detailed information during execution"
    echo "  --excluded COMPONENT1,COMPONENT2   Components to exclude from deletion (comma-separated)"
    echo "  --clusterconfig FILE               Path to input.json (reads exclude_components, kubernetes_distribution, namespaces)"
    echo "  --istioNamespace NAMESPACE         Custom namespace for Istio components (default: istio-system)"
    echo "  --uipathNamespace NAMESPACE        Custom namespace for UiPath components (default: uipath)"
    echo "  --argocdNamespace NAMESPACE        Custom namespace for ArgoCD components (default: argocd)"
    echo "  --shared-argocd                    Mark ArgoCD as shared and do not delete it"
    echo
    echo "Examples:"
    echo "  $0 k8s --excluded istio,redis                # Keep istio and redis components, delete all others"
    echo "  $0 openshift --dry-run                              # Show what would be deleted without actually deleting"
    echo "  $0 openshift --clusterconfig cluster_config.json    # Read excluded components from JSON file"
    echo "  $0 k8s --uipathNamespace custom-uipath       # Use custom namespace for UiPath components"
    echo
    echo "Available components:"
    get_all_components | tr ' ' '\n' | sort | sed 's/^/  - /'
    echo
}

function check_prerequisites {
    if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
        if ! command -v oc > /dev/null; then
            echo "Error: oc (OpenShift CLI) is not installed or not in PATH"
            exit 1
        fi
        K8S_CMD="oc"
    else
        if ! command -v kubectl > /dev/null; then
            echo "Error: kubectl is not installed or not in PATH"
            exit 1
        fi
        K8S_CMD="kubectl"
    fi

    if ! command -v helm > /dev/null; then
        echo "Error: helm is not installed or not in PATH"
        exit 1
    fi

    if [ -n "$CLUSTER_CONFIG_FILE" ]; then
        if ! command -v jq > /dev/null; then
            echo "Warning: jq is not installed. Will use basic JSON parsing for configuration."
        fi

        if [ ! -f "$CLUSTER_CONFIG_FILE" ]; then
            echo "Error: Cluster configuration file '$CLUSTER_CONFIG_FILE' not found"
            exit 1
        fi
    fi
}

function get_all_components {
    local components="uipath istio argocd cert_manager network_policies istio_configure"
    if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
        components="$components shared_gitops"
    else
        components="$components gatekeeper authentication"
    fi

    echo "$components"
}

function map_component_name {
    local component="$1"
    
    # Map dash-separated names to underscore-separated names
    case "$component" in
        "cert-manager")
            echo "cert_manager"
            ;;
        "network-policies")
            echo "network_policies"
            ;;
        "istio-configure")
            echo "istio_configure"
            ;;
        *)
            echo "$component"
            ;;
    esac
}

function read_excluded_from_json {
    local file="$1"

    if [ -f "$file" ]; then
        if command -v jq >/dev/null 2>&1; then
            if jq -e '.exclude_components' "$file" >/dev/null 2>&1; then
                local excluded_json
                excluded_json=$(jq -r '.exclude_components | join(",")' "$file")
                if [ "$excluded_json" != "null" ] && [ -n "$excluded_json" ]; then
                    echo "$excluded_json"
                fi
            fi
        else
            local components
            components=$(grep -o '"exclude_components"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$file" |
                          sed 's/.*\[\(.*\)\].*/\1/g' |
                          sed 's/"//g' |
                          sed 's/[[:space:]]//g')
            echo "$components"
        fi
    fi
}

function read_config_from_json {
    local file="$1"

    if [ ! -f "$file" ]; then
        return
    fi

    if ! command -v jq >/dev/null 2>&1; then
        return
    fi

    # Read kubernetes_distribution from input.json if not explicitly set via CLI
    if [ "$K8S_DISTRIBUTION" = "k8s" ]; then
        local dist
        dist=$(jq -r '.kubernetes_distribution // empty' "$file" 2>/dev/null)
        if [ -n "$dist" ]; then
            case "$dist" in
                openshift)
                    K8S_DISTRIBUTION="openshift"
                    ;;
                eks|aks)
                    K8S_DISTRIBUTION="k8s"
                    ;;
            esac
        fi
    fi

    # Read namespace overrides from input.json if not explicitly set via CLI
    local json_ns
    json_ns=$(jq -r '.namespace // empty' "$file" 2>/dev/null)
    if [ -n "$json_ns" ] && [ "$UIPATH_NAMESPACE" = "uipath" ]; then
        UIPATH_NAMESPACE="$json_ns"
    fi

    local json_istio_ns
    json_istio_ns=$(jq -r '.ingress.namespace // empty' "$file" 2>/dev/null)
    if [ -n "$json_istio_ns" ] && [ "$ISTIO_NAMESPACE" = "istio-system" ]; then
        ISTIO_NAMESPACE="$json_istio_ns"
    fi

    local json_argocd_ns
    json_argocd_ns=$(jq -r '.argocd.application_namespace // empty' "$file" 2>/dev/null)
    if [ -n "$json_argocd_ns" ] && [ "$ARGOCD_NAMESPACE" = "argocd" ]; then
        ARGOCD_NAMESPACE="$json_argocd_ns"
    fi
}

function parse_component_resources {
    local component_def="$1"
    local helm_charts=""
    local namespaces=""
    local roles=""
    local rolebindings=""
    local argocd_apps=""
    local operators=""
    local priority_classes=""
    local sccs=""
    local crds=""

    local type resource res_name res_ns

    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$line" ] && continue

        type=$(echo "$line" | cut -d: -f1)
        resource=$(echo "$line" | cut -d: -f2-)

        case "$type" in
            "helm")
                if echo "$resource" | grep -q ":"; then
                    res_name=$(echo "$resource" | cut -d: -f1)
                    res_ns=$(echo "$resource" | cut -d: -f2)
                    helm_charts="$helm_charts $res_name:$res_ns"
                    if ! echo "$namespaces" | grep -q "[[:space:]]${res_ns}[[:space:]]"; then
                        namespaces="$namespaces $res_ns"
                    fi
                else
                    helm_charts="$helm_charts $resource"
                fi
                ;;
            "role")
                if echo "$resource" | grep -q ":"; then
                    res_name=$(echo "$resource" | cut -d: -f1)
                    res_ns=$(echo "$resource" | cut -d: -f2)
                    roles="$roles $res_name:$res_ns"
                    IFS=',' read -r -a NS_ARRAY <<< "$res_ns"
                    for ns in "${NS_ARRAY[@]}"; do
                        if ! echo "$namespaces" | grep -q "[[:space:]]${ns}[[:space:]]"; then
                            namespaces="$namespaces $ns"
                        fi
                    done
                else
                    roles="$roles $resource"
                fi
                ;;
            "rolebinding")
                if echo "$resource" | grep -q ":"; then
                    res_name=$(echo "$resource" | cut -d: -f1)
                    res_ns=$(echo "$resource" | cut -d: -f2)
                    rolebindings="$rolebindings $res_name:$res_ns"
                    IFS=',' read -r -a NS_ARRAY <<< "$res_ns"
                    for ns in "${NS_ARRAY[@]}"; do
                        if ! echo "$namespaces" | grep -q "[[:space:]]${ns}[[:space:]]"; then
                            namespaces="$namespaces $ns"
                        fi
                    done
                else
                    rolebindings="$rolebindings $resource"
                fi
                ;;
            "argocd")
                argocd_apps="$argocd_apps $resource"
                ;;
            "namespace")
                if ! echo "$namespaces" | grep -q "[[:space:]]${resource}[[:space:]]"; then
                    namespaces="$namespaces $resource"
                fi
                ;;
            "operator")
                operators="$operators $resource"
                ;;
            "priorityclass")
                priority_classes="$priority_classes $resource"
                ;;
            "scc")
                sccs="$sccs $resource"
                ;;
            "crd")
                crds="$crds $resource"
                ;;
        esac
    done <<< "$component_def"

    helm_charts=$(echo "$helm_charts" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    namespaces=$(echo "$namespaces" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    roles=$(echo "$roles" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    rolebindings=$(echo "$rolebindings" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    argocd_apps=$(echo "$argocd_apps" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    operators=$(echo "$operators" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    priority_classes=$(echo "$priority_classes" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    sccs=$(echo "$sccs" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    crds=$(echo "$crds" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    echo "HELM_CHARTS=\"$helm_charts\""
    echo "NAMESPACES=\"$namespaces\""
    echo "ROLES=\"$roles\""
    echo "ROLEBINDINGS=\"$rolebindings\""
    echo "ARGOCD_APPS=\"$argocd_apps\""
    echo "OPERATORS=\"$operators\""
    echo "PRIORITY_CLASSES=\"$priority_classes\""
    echo "SCCS=\"$sccs\""
    echo "CRDS=\"$crds\""
}

function delete_helm_chart {
    local chart=$1
    local namespace=$2

    if [ -n "$namespace" ]; then
        if $DRY_RUN; then
            echo "DRY-RUN: Would uninstall helm chart: $chart in namespace $namespace"
        else
            if $VERBOSE; then
                echo "Uninstalling helm chart: $chart in namespace $namespace"
            fi
            # Check if the release exists before trying to uninstall
            if helm list -n "$namespace" | grep -q "^${chart}[[:space:]]"; then
                helm uninstall "$chart" -n "$namespace" || echo "Failed to uninstall $chart in $namespace"
            else
                if $VERBOSE; then
                    echo "Helm release $chart not found in namespace $namespace, skipping"
                fi
            fi
        fi
    else
        if $DRY_RUN; then
            echo "DRY-RUN: Would uninstall helm chart: $chart (default namespace)"
        else
            if $VERBOSE; then
                echo "Uninstalling helm chart: $chart (default namespace)"
            fi
            # Check if the release exists before trying to uninstall
            if helm list | grep -q "^${chart}[[:space:]]"; then
                helm uninstall "$chart" || echo "Failed to uninstall $chart"
            else
                if $VERBOSE; then
                    echo "Helm release $chart not found, skipping"
                fi
            fi
        fi
    fi
}

function delete_role {
    local role=$1
    local namespace=$2

    if [ -n "$namespace" ]; then
        if $DRY_RUN; then
            echo "DRY-RUN: Would delete role: $role in namespace $namespace"
        else
            if $VERBOSE; then
                echo "Deleting role: $role in namespace $namespace"
            fi
            $K8S_CMD delete role "$role" -n "$namespace" --ignore-not-found=true
        fi
    else
        if $DRY_RUN; then
            echo "DRY-RUN: Would delete clusterrole: $role"
        else
            if $VERBOSE; then
                echo "Deleting clusterrole: $role"
            fi
            $K8S_CMD delete clusterrole "$role" --ignore-not-found=true
        fi
    fi
}

function delete_rolebinding {
    local rolebinding=$1
    local namespace=$2

    if [ -n "$namespace" ]; then
        if $DRY_RUN; then
            echo "DRY-RUN: Would delete rolebinding: $rolebinding in namespace $namespace"
        else
            if $VERBOSE; then
                echo "Deleting rolebinding: $rolebinding in namespace $namespace"
            fi
            $K8S_CMD delete rolebinding "$rolebinding" -n "$namespace" --ignore-not-found=true
        fi
    else
        if $DRY_RUN; then
            echo "DRY-RUN: Would delete clusterrolebinding: $rolebinding"
        else
            if $VERBOSE; then
                echo "Deleting clusterrolebinding: $rolebinding"
            fi
            $K8S_CMD delete clusterrolebinding "$rolebinding" --ignore-not-found=true
        fi
    fi
}

function delete_argocd_app {
  local apps="$1"

  if $DRY_RUN; then
    echo "DRY-RUN: Would delete ArgoCD applications: $apps"
    return
  fi

  if $VERBOSE; then
    echo "Triggering deletion of ArgoCD applications: $apps"
  fi

  # Determine which namespaces to check based on K8S_DISTRIBUTION
  local namespaces=("$ARGOCD_NAMESPACE")
  if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
    namespaces+=("openshift-gitops")
  fi

  # For each namespace, remove finalizers first (foreground), then delete (background)
  for ns in "${namespaces[@]}"; do
    local apps_in_namespace=""

    for app in $apps; do
      # Check if the app exists in this namespace (suppress output if not found)
      local app_json
      app_json=$($K8S_CMD get applications.argoproj.io "$app" -n "$ns" -o jsonpath='{.metadata.name}' 2>/dev/null)
      if [ -z "$app_json" ]; then
        continue
      fi

      # Remove finalizers in foreground - must complete before delete
      local has_finalizers
      has_finalizers=$($K8S_CMD get applications.argoproj.io "$app" -n "$ns" -o jsonpath='{.metadata.finalizers[0]}' 2>/dev/null)
      if [ -n "$has_finalizers" ] && [ "$has_finalizers" != "null" ]; then
        if $VERBOSE; then
          echo "Removing finalizers from application $app in namespace $ns"
        fi
        $K8S_CMD patch applications.argoproj.io "$app" -n "$ns" --type json --patch='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
      fi

      if [ -z "$apps_in_namespace" ]; then
        apps_in_namespace="$app"
      else
        apps_in_namespace="$apps_in_namespace $app"
      fi
    done

    # Delete all found applications in this namespace in one command (background)
    if [ -n "$apps_in_namespace" ]; then
      if $VERBOSE; then
        echo "Deleting applications in namespace $ns: $apps_in_namespace"
      fi
      $K8S_CMD delete applications.argoproj.io $apps_in_namespace -n "$ns" --ignore-not-found=true &
    fi
  done
}

function wait_for_argocd_apps_deletion {
  local apps="$1"

  if $DRY_RUN; then
    echo "DRY-RUN: Would wait for ArgoCD applications to be deleted"
    return
  fi

  if $VERBOSE; then
    echo "Waiting for ArgoCD applications to be deleted..."
  fi

  # Determine which namespaces to check based on K8S_DISTRIBUTION
  local namespaces=("$ARGOCD_NAMESPACE")
  if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
    namespaces+=("openshift-gitops")
  fi

  # Wait for background deletion jobs to complete
  wait

  # Poll only our specific apps until they are gone
  local max_attempts=30
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    local still_exists=false

    for app in $apps; do
      for ns in "${namespaces[@]}"; do
        if $K8S_CMD get applications.argoproj.io "$app" -n "$ns" >/dev/null 2>&1; then
          still_exists=true

          # Check if stuck (has deletionTimestamp + finalizers)
          local finalizer
          finalizer=$($K8S_CMD get applications.argoproj.io "$app" -n "$ns" -o jsonpath='{.metadata.finalizers[0]}' 2>/dev/null)
          local deleting
          deleting=$($K8S_CMD get applications.argoproj.io "$app" -n "$ns" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null)

          if [ -n "$deleting" ] && [ -n "$finalizer" ] && [ "$finalizer" != "null" ]; then
            if $VERBOSE; then
              echo "Application $app stuck in namespace $ns - removing finalizer"
            fi
            $K8S_CMD patch applications.argoproj.io "$app" -n "$ns" --type json --patch='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
          fi
        fi
      done
    done

    if [ "$still_exists" = false ]; then
      if $VERBOSE; then
        echo "All targeted ArgoCD applications have been deleted."
      fi
      return
    fi

    sleep 2
    attempt=$((attempt + 1))
  done

  echo "Warning: Some ArgoCD applications may still be in deletion process after $((max_attempts * 2)) seconds."
  echo "You may need to manually check remaining applications."
}

function delete_namespace {
    local namespace=$1

    if $DRY_RUN; then
        if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
            echo "DRY-RUN: Would delete namespace/project: $namespace"
        else
            echo "DRY-RUN: Would delete namespace: $namespace"
        fi
    else
        if $VERBOSE; then
            if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
                echo "Deleting namespace/project: $namespace"
            else
                echo "Deleting namespace: $namespace"
            fi
        fi

        if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
            $K8S_CMD delete project "$namespace" --ignore-not-found=true
        else
            $K8S_CMD delete namespace "$namespace" --ignore-not-found=true
        fi
    fi
}

function delete_priority_class {
    local priority_class=$1

    if $DRY_RUN; then
        echo "DRY-RUN: Would delete priority class: $priority_class"
    else
        if $VERBOSE; then
            echo "Deleting priority class: $priority_class"
        fi
        $K8S_CMD delete priorityclass "$priority_class" --ignore-not-found=true
    fi
}

function delete_operator {
    local operator=$1

    if $DRY_RUN; then
        echo "DRY-RUN: Would delete operator subscription: $operator"
    else
        if $VERBOSE; then
            echo "Deleting operator subscription: $operator"
        fi
        $K8S_CMD delete subscription "$operator" -n openshift-operators --ignore-not-found=true

        local csv
        csv=$($K8S_CMD get clusterserviceversion | grep "$operator" | awk '{print $1}')
        if [ -n "$csv" ]; then
            if $VERBOSE; then
                echo "Deleting clusterserviceversion: $csv"
            fi
            $K8S_CMD delete clusterserviceversion "$csv" -n openshift-operators --ignore-not-found=true
        fi
    fi
}

function delete_scc {
    local scc=$1

    if $DRY_RUN; then
        echo "DRY-RUN: Would delete security context constraint: $scc"
    else
        if $VERBOSE; then
            echo "Deleting security context constraint: $scc"
        fi
        $K8S_CMD delete scc "$scc" --ignore-not-found=true
    fi
}

function delete_crd_instances {
    local crd=$1

    if $DRY_RUN; then
        echo "DRY-RUN: Would delete all instances of CRD: $crd"
    else
        if $VERBOSE; then
            echo "Deleting all instances of CRD: $crd"
        fi

        if $K8S_CMD get crd "$crd" >/dev/null 2>&1; then
            # Use the CRD name directly as the resource type (e.g. applications.argoproj.io)
            # This avoids fragile api-resources parsing that can conflate similar names
            local instances=""
            instances=$($K8S_CMD get "$crd" --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null | tr -d '\r')

            if [ -n "$instances" ]; then
                local ns name
                while IFS= read -r line; do
                    [ -z "$line" ] && continue
                    ns=$(echo "$line" | awk '{print $1}')
                    name=$(echo "$line" | awk '{print $2}')

                    if $VERBOSE; then
                        echo "Deleting $crd: $name in namespace $ns"
                    fi
                    $K8S_CMD delete "$crd" "$name" -n "$ns" --ignore-not-found=true
                done <<< "$instances"
            fi
        else
            if $VERBOSE; then
                echo "CRD $crd not found, skipping."
            fi
        fi
    fi
}

function delete_component {
    local component_name=$1

    echo "Processing component for deletion: $component_name"

    # Use a subshell to catch any errors and continue
    (
        local component_def
        eval "component_def=\"\${$component_name}\""

        local temp_file
        temp_file=$(mktemp)
        parse_component_resources "$component_def" > "$temp_file"
        # shellcheck disable=SC1090  # Dynamic source from temp file
        source "$temp_file"
        rm -f "$temp_file"

        for crd in $CRDS; do
            delete_crd_instances "$crd"
        done

        # Delete ArgoCD applications: remove finalizers (foreground), delete (background), then wait
        if [ -n "$ARGOCD_APPS" ]; then
            delete_argocd_app "$ARGOCD_APPS"
            wait_for_argocd_apps_deletion "$ARGOCD_APPS"
        fi

        local chart_name chart_ns binding_name binding_namespaces role_name role_namespaces
        for chart in $HELM_CHARTS; do
            if echo "$chart" | grep -q ":"; then
                chart_name=$(echo "$chart" | cut -d':' -f1)
                chart_ns=$(echo "$chart" | cut -d':' -f2)
                delete_helm_chart "$chart_name" "$chart_ns"
            else
                delete_helm_chart "$chart" ""
            fi
        done

        for binding in $ROLEBINDINGS; do
            if echo "$binding" | grep -q ":"; then
                binding_name=$(echo "$binding" | cut -d':' -f1)
                binding_namespaces=$(echo "$binding" | cut -d':' -f2 | tr ',' ' ')

                for ns in $binding_namespaces; do
                    delete_rolebinding "$binding_name" "$ns"
                done
            else
                delete_rolebinding "$binding" ""
            fi
        done

        for role in $ROLES; do
            if echo "$role" | grep -q ":"; then
                role_name=$(echo "$role" | cut -d':' -f1)
                role_namespaces=$(echo "$role" | cut -d':' -f2 | tr ',' ' ')

                for ns in $role_namespaces; do
                    delete_role "$role_name" "$ns"
                done
            else
                delete_role "$role" ""
            fi
        done

        for pc in $PRIORITY_CLASSES; do
            delete_priority_class "$pc"
        done

        if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
            for op in $OPERATORS; do
                delete_operator "$op"
            done
        fi

        if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
            for sc in $SCCS; do
                delete_scc "$sc"
            done
        fi

        for ns in $NAMESPACES; do
            delete_namespace "$ns"
        done

        echo "Completed processing component: $component_name"
        echo
    ) || {
        echo "Warning: Error occurred while processing component '$component_name'. Continuing with next component..."
        echo
    }
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
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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
            --shared-argocd)
                ARGOCD_SHARED=true
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
        IFS=',' read -r -a CLI_EXCLUDED <<< "$excluded_arg"
        for comp in "${CLI_EXCLUDED[@]}"; do
            EXCLUDED_COMPONENTS+=("$(map_component_name "$comp")")
        done
    fi

    if [ -n "$CLUSTER_CONFIG_FILE" ]; then
        # Read distribution and namespace overrides from input.json before defining components
        read_config_from_json "$CLUSTER_CONFIG_FILE"

        excluded_from_json=$(read_excluded_from_json "$CLUSTER_CONFIG_FILE")
        if [ -n "$excluded_from_json" ]; then
            IFS=',' read -r -a JSON_EXCLUDED <<< "$excluded_from_json"
            for comp in "${JSON_EXCLUDED[@]}"; do
                EXCLUDED_COMPONENTS+=("$(map_component_name "$comp")")
            done
        fi
    fi

    echo "Distribution: $K8S_DISTRIBUTION"
    echo "UiPath namespace: $UIPATH_NAMESPACE"
    echo "ArgoCD namespace: $ARGOCD_NAMESPACE"
    echo "Istio namespace: $ISTIO_NAMESPACE"
    echo

    define_components

    local all_components
    all_components=$(get_all_components)
    read -r -a all_components_array <<< "$all_components"

    if [ ${#EXCLUDED_COMPONENTS[@]} -gt 0 ]; then
        local temp_file
        temp_file=$(mktemp)

        for comp in "${EXCLUDED_COMPONENTS[@]}"; do
            echo "$comp" >> "$temp_file"
        done

        EXCLUDED_COMPONENTS=()
        while read -r comp; do
            [ -z "$comp" ] && continue
            EXCLUDED_COMPONENTS+=("$comp")
        done < <(sort -u "$temp_file")

        rm -f "$temp_file"
    fi

    if [ ${#EXCLUDED_COMPONENTS[@]} -eq 0 ]; then
        echo "No components specified to keep. All components will be deleted."
    else
        echo "Components to keep: ${EXCLUDED_COMPONENTS[*]}"
    fi

    for comp in "${EXCLUDED_COMPONENTS[@]}"; do
        local found=false
        for available in "${all_components_array[@]}"; do
            if [ "$comp" = "$available" ]; then
                found=true
                break
            fi
        done

        if [ "$found" = false ]; then
            echo "Warning: Component '$comp' is not recognized and will be ignored."
        fi
    done

    local components_to_delete=()
    for comp in "${all_components_array[@]}"; do
        local should_delete=true
        for excluded in "${EXCLUDED_COMPONENTS[@]}"; do
            if [ "$comp" = "$excluded" ]; then
                should_delete=false
                break
            fi
        done

        if [ "$should_delete" = true ]; then
            components_to_delete+=("$comp")
        fi
    done

    if $ARGOCD_SHARED; then
        # Remove argocd and shared_gitops from components_to_delete if present
        new_components=()
        for comp in "${components_to_delete[@]}"; do
            if [ "$comp" != "argocd" ] && [ "$comp" != "shared_gitops" ]; then
                new_components+=("$comp")
            fi
        done
        components_to_delete=("${new_components[@]}")
    fi

    echo "Components to delete: ${components_to_delete[*]}"
    echo

    local failed_components=()
    for comp in "${components_to_delete[@]}"; do
        if ! delete_component "$comp"; then
            failed_components+=("$comp")
        fi
    done

    if [ ${#failed_components[@]} -gt 0 ]; then
        echo "Warning: The following components encountered errors during deletion:"
        for comp in "${failed_components[@]}"; do
            echo "  - $comp"
        done
        echo
    fi

    if $DRY_RUN; then
        echo "Dry run completed. No changes were made."
    else
        if [ ${#failed_components[@]} -eq 0 ]; then
            echo "All specified components have been deleted successfully."
        else
            echo "Deletion completed with some errors. Check the warnings above."
        fi
    fi

    if $ARGOCD_SHARED; then
        echo "Disclaimer: ArgoCD is marked as shared (--shared-argocd), so it was not deleted."
    fi
}

main "$@"