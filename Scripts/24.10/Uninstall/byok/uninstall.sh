#!/bin/bash

set -e

K8S_DISTRIBUTION="k8s"
DRY_RUN=false
VERBOSE=false
EXCLUDED_COMPONENTS=()
CLUSTER_CONFIG_FILE=""
ISTIO_NAMESPACE="istio-system"
UIPATH_NAMESPACE="uipath"
ARGOCD_NAMESPACE="argocd"
ARGOCD_SHARED=false


function define_components {
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

    istio_configure="
      helm:istio-configure:${ISTIO_NAMESPACE}
    "

#    if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
#        istio+="
#        operator:servicemesh-operator
#        "
#    fi

    argocd="
    role:argo-secret-role:${ARGOCD_NAMESPACE}
    role:uipath-application-manager:${ARGOCD_NAMESPACE}
    rolebinding:secret-binding:${ARGOCD_NAMESPACE}
    "

    if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
        # For OpenShift, only delete applications, not infrastructure, and DO NOT delete the namespace
        echo "choosing openshift based ArgoCD configuration"
        argocd="
        role:argo-secret-role:${ARGOCD_NAMESPACE}
        role:uipath-application-manager:${ARGOCD_NAMESPACE}
        rolebinding:secret-binding:${ARGOCD_NAMESPACE}
        crd:applications.argoproj.io
        rolebinding:uipath-application-manager:${ARGOCD_NAMESPACE}
        rolebinding:namespace-reader-rolebinding:${ARGOCD_NAMESPACE}
        "
    else
        echo "choosing non-openshift (eks/aks) based ArgoCD configuration"
        argocd+="
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
        scc:anyuid
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

    if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
        cert_manager="
        role:argocd-cert-manager-role:${UIPATH_NAMESPACE}
        rolebinding:argocd-cert-manager-binding:${UIPATH_NAMESPACE}
        rolebinding:gitops-cert-manager-binding:${UIPATH_NAMESPACE}
        operator:cert-manager
        crd:certificates.cert-manager.io
        crd:issuers.cert-manager.io
        crd:clusterissuers.cert-manager.io
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
    gatekeeper="
    helm:gatekeeper:gatekeeper-system
    "

    falco="
      helm:falco:falco
      "
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
    echo "  --clusterconfig FILE               Path to cluster configuration JSON file with excluded_components array"
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
        if ! command -v oc; then
            echo "Error: oc (OpenShift CLI) is not installed or not in PATH"
            exit 1
        fi
        K8S_CMD="oc"
    else
        if ! command -v kubectl; then
            echo "Error: kubectl is not installed or not in PATH"
            exit 1
        fi
        K8S_CMD="kubectl"
    fi

    if ! command -v helm; then
        echo "Error: helm is not installed or not in PATH"
        exit 1
    fi

    if [ -n "$CLUSTER_CONFIG_FILE" ]; then
        if ! command -v jq; then
            echo "Warning: jq is not installed. Will use basic JSON parsing for configuration."
        fi

        if [ ! -f "$CLUSTER_CONFIG_FILE" ]; then
            echo "Error: Cluster configuration file '$CLUSTER_CONFIG_FILE' not found"
            exit 1
        fi
    fi
}

function get_all_components {
    local components="uipath istio argocd cert_manager network_policies gatekeeper falco istio_configure"
    if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
        components="$components shared_gitops"
    else
        components="$components"
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
                local excluded_json=$(jq -r '.exclude_components | join(",")' "$file")
                if [ "$excluded_json" != "null" ] && [ -n "$excluded_json" ]; then
                    echo "$excluded_json"
                fi
            fi
        else
            local components=$(grep -o '"exclude_components"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$file" |
                          sed 's/.*\[\(.*\)\].*/\1/g' |
                          sed 's/"//g' |
                          sed 's/[[:space:]]//g')
            echo "$components"
        fi
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

    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$line" ] && continue

        local type=$(echo "$line" | cut -d: -f1)
        local resource=$(echo "$line" | cut -d: -f2-)

        case "$type" in
            "helm")
                if echo "$resource" | grep -q ":"; then
                    local res_name=$(echo "$resource" | cut -d: -f1)
                    local res_ns=$(echo "$resource" | cut -d: -f2)
                    helm_charts="$helm_charts $res_name:$res_ns"
                    if ! echo "$namespaces" | grep -q "[[:space:]]$res_ns[[:space:]]"; then
                        namespaces="$namespaces $res_ns"
                    fi
                else
                    helm_charts="$helm_charts $resource"
                fi
                ;;
            "role")
                if echo "$resource" | grep -q ":"; then
                    local res_name=$(echo "$resource" | cut -d: -f1)
                    local res_ns=$(echo "$resource" | cut -d: -f2)
                    roles="$roles $res_name:$res_ns"
                    IFS=',' read -r -a NS_ARRAY <<< "$res_ns"
                    for ns in "${NS_ARRAY[@]}"; do
                        if ! echo "$namespaces" | grep -q "[[:space:]]$ns[[:space:]]"; then
                            namespaces="$namespaces $ns"
                        fi
                    done
                else
                    roles="$roles $resource"
                fi
                ;;
            "rolebinding")
                if echo "$resource" | grep -q ":"; then
                    local res_name=$(echo "$resource" | cut -d: -f1)
                    local res_ns=$(echo "$resource" | cut -d: -f2)
                    rolebindings="$rolebindings $res_name:$res_ns"
                    IFS=',' read -r -a NS_ARRAY <<< "$res_ns"
                    for ns in "${NS_ARRAY[@]}"; do
                        if ! echo "$namespaces" | grep -q "[[:space:]]$ns[[:space:]]"; then
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
                if ! echo "$namespaces" | grep -q "[[:space:]]$resource[[:space:]]"; then
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
            if helm list -n "$namespace" | grep -q "^$chart[[:space:]]"; then
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
            if helm list | grep -q "^$chart[[:space:]]"; then
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
  
  # Group applications by namespace and delete in single commands
  for ns in "${namespaces[@]}"; do
    local apps_in_namespace=""
    
    # Check each application to see if it exists in this namespace
    for app in $apps; do
      if $K8S_CMD get applications.argoproj.io "$app" -n "$ns" --ignore-not-found=true >/dev/null 2>&1; then
        # Check if application has finalizers and remove them first
        local has_finalizers=$($K8S_CMD get applications.argoproj.io "$app" -n "$ns" -o jsonpath='{.metadata.finalizers[0]}' 2>&1)
        
        if [ -n "$has_finalizers" ] && [ "$has_finalizers" != "null" ]; then
          if $VERBOSE; then
            echo "Removing finalizers from application $app in namespace $ns"
          fi
          # Remove finalizers using patch (run in background)
          $K8S_CMD patch applications.argoproj.io "$app" -n "$ns" --type json --patch='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null &
        fi
        
        # Add to the list for single command deletion
        if [ -z "$apps_in_namespace" ]; then
          apps_in_namespace="$app"
        else
          apps_in_namespace="$apps_in_namespace $app"
        fi
      fi
    done
    
    # Delete all applications in this namespace in ONE command (like: kubectl delete application app1 app2 app3)
    if [ -n "$apps_in_namespace" ]; then
      if $VERBOSE; then
        echo "Deleting applications in namespace $ns: $K8S_CMD delete applications.argoproj.io $apps_in_namespace -n $ns"
      fi
      $K8S_CMD delete applications.argoproj.io $apps_in_namespace -n "$ns" --ignore-not-found=true &
    fi
  done
}

function force_remove_argocd_finalizers {
  if $DRY_RUN; then
    echo "DRY-RUN: Would force remove finalizers from stuck ArgoCD applications"
    return
  fi

  if $VERBOSE; then
    echo "Checking for stuck ArgoCD applications and forcing finalizer removal..."
  fi

  # Determine which namespaces to check based on K8S_DISTRIBUTION
  local namespaces=("$ARGOCD_NAMESPACE")
  if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
    namespaces+=("openshift-gitops")
  fi
  
  for ns in "${namespaces[@]}"; do
    # Get all applications with finalizers
    local apps_with_finalizers=$($K8S_CMD get applications.argoproj.io -n "$ns" -o jsonpath='{range .items[?(@.metadata.finalizers)]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
    
    if [ -n "$apps_with_finalizers" ]; then
      while IFS= read -r app_name; do
        [ -z "$app_name" ] && continue
        
        if $VERBOSE; then
          echo "Forcing removal of finalizers from application: $app_name in namespace $ns"
        fi
        
        # Force remove finalizers using multiple methods (run in background)
        $K8S_CMD patch applications.argoproj.io "$app_name" -n "$ns" --type json --patch='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null &
        
        # Also try to force delete with immediate grace period (run in background)
        $K8S_CMD delete applications.argoproj.io "$app_name" -n "$ns" --ignore-not-found=true --force --grace-period=0 2>/dev/null &
        
      done <<< "$apps_with_finalizers"
    fi
  done
}

function wait_for_argocd_apps_deletion {
  if $DRY_RUN; then
    echo "DRY-RUN: Would wait for ArgoCD applications to be deleted"
    return
  fi

  if $VERBOSE; then
    echo "Waiting for all ArgoCD applications to be deleted..."
  fi

  # Determine which namespaces to check based on K8S_DISTRIBUTION
  local namespaces=("$ARGOCD_NAMESPACE")
  if [ "$K8S_DISTRIBUTION" = "openshift" ]; then
    namespaces+=("openshift-gitops")
  fi
  
  # Wait for all background deletion jobs to complete
  wait

  # Additional wait to ensure all applications are fully deleted
  local max_attempts=30
  local attempt=0
  local all_deleted=false

  while [ $attempt -lt $max_attempts ] && [ "$all_deleted" = false ]; do
    all_deleted=true
    
    for ns in "${namespaces[@]}"; do
      # Check if any applications still exist
      local remaining_apps=$($K8S_CMD get applications.argoproj.io -n "$ns" --no-headers 2>/dev/null | wc -l)
      if [ "$remaining_apps" -gt 0 ]; then
        all_deleted=false
        
        # Check for stuck applications with finalizers or deletion errors
        local stuck_apps=$($K8S_CMD get applications.argoproj.io -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{" "}{.metadata.finalizers[0]}{" "}{.status.conditions[?(@.type=="DeletionError")].message}{"\n"}{end}' 2>/dev/null)
        
        if [ -n "$stuck_apps" ]; then
          while IFS= read -r line; do
            [ -z "$line" ] && continue
            local app_name=$(echo "$line" | awk '{print $1}')
            local deletion_timestamp=$(echo "$line" | awk '{print $2}')
            local finalizer=$(echo "$line" | awk '{print $3}')
            local error_msg=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
            
            # If app has deletion timestamp and finalizer, force remove finalizer
            if [ -n "$deletion_timestamp" ] && [ -n "$finalizer" ] && [ "$finalizer" != "null" ]; then
              if $VERBOSE; then
                echo "Application $app_name is stuck in deletion. Forcing removal of finalizer: $finalizer"
                if [ -n "$error_msg" ]; then
                  echo "  Error: $error_msg"
                fi
              fi
              
              # Force remove finalizers
              $K8S_CMD patch applications.argoproj.io "$app_name" -n "$ns" --type json --patch='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null
              
              # Also try to force delete the application
              $K8S_CMD delete applications.argoproj.io "$app_name" -n "$ns" --ignore-not-found=true --force --grace-period=0 2>/dev/null
            fi
          done <<< "$stuck_apps"
        fi
        
        if $VERBOSE; then
          echo "Still waiting for $remaining_apps applications to be deleted in namespace $ns..."
        fi
        break
      fi
    done

    if [ "$all_deleted" = false ]; then
      sleep 2
      attempt=$((attempt + 1))
    fi
  done

  if [ "$all_deleted" = true ]; then
    if $VERBOSE; then
      echo "All ArgoCD applications have been successfully deleted."
    fi
  else
    echo "Warning: Some ArgoCD applications may still be in deletion process after $((max_attempts * 2)) seconds."
    echo "You may need to manually force delete remaining applications."
  fi
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

        local csv=$($K8S_CMD get clusterserviceversion | grep "$operator" | awk '{print $1}')
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
            # Get the API group from the CRD
            local api_group=$(echo "$crd" | cut -d. -f2-)
            local resource_name=$(echo "$crd" | cut -d. -f1)
            
            # Get the API resource more safely
            local api_resource=""
            if [ -n "$api_group" ]; then
                api_resource=$($K8S_CMD api-resources --api-group="$api_group" 2>/dev/null | grep "^$resource_name[[:space:]]" | head -1 | awk '{print $1}')
            else
                api_resource=$($K8S_CMD api-resources 2>/dev/null | grep "^$resource_name[[:space:]]" | head -1 | awk '{print $1}')
            fi

            if [ -n "$api_resource" ]; then
                if $VERBOSE; then
                    echo "Found API resource: $api_resource for CRD: $crd"
                fi
                
                # Get instances more safely
                local instances=""
                if [ "$api_group" = "argoproj.io" ]; then
                    # Special handling for ArgoCD resources
                    instances=$($K8S_CMD get "$api_resource" --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null | tr -d '\r')
                else
                    instances=$($K8S_CMD get "$api_resource" --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null | tr -d '\r')
                fi

                if [ -n "$instances" ]; then
                    while IFS= read -r line; do
                        [ -z "$line" ] && continue
                        local ns=$(echo "$line" | awk '{print $1}')
                        local name=$(echo "$line" | awk '{print $2}')

                        if $VERBOSE; then
                            echo "Deleting $api_resource: $name in namespace $ns"
                        fi
                        $K8S_CMD delete "$api_resource" "$name" -n "$ns" --ignore-not-found=true
                    done <<< "$instances"
                fi
            else
                if $VERBOSE; then
                    echo "Could not determine API resource for CRD: $crd"
                fi
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
        set -e  # Exit on error within this subshell
        
        local component_def
        eval "component_def=\"\${$component_name}\""

        local temp_file
        temp_file=$(mktemp)
        parse_component_resources "$component_def" > "$temp_file"
        source "$temp_file"
        rm -f "$temp_file"

        for crd in $CRDS; do
            delete_crd_instances "$crd"
        done

        # Force remove finalizers from any stuck ArgoCD applications first
        if [ -n "$ARGOCD_APPS" ]; then
            force_remove_argocd_finalizers
        fi

        # Trigger all ArgoCD application deletions in parallel
        if [ -n "$ARGOCD_APPS" ]; then
            if $DRY_RUN; then
                echo "DRY-RUN: Would delete ArgoCD applications: $ARGOCD_APPS"
            else
                if $VERBOSE; then
                    echo "Triggering parallel deletion of ArgoCD applications: $ARGOCD_APPS"
                fi
                
                # Delete each ArgoCD application in parallel
                delete_argocd_app "$ARGOCD_APPS"
                
                # Wait for all ArgoCD applications to be deleted
                wait_for_argocd_apps_deletion
            fi
        fi

        for chart in $HELM_CHARTS; do
            if echo "$chart" | grep -q ":"; then
                local chart_name=$(echo "$chart" | cut -d':' -f1)
                local chart_ns=$(echo "$chart" | cut -d':' -f2)
                delete_helm_chart "$chart_name" "$chart_ns"
            else
                delete_helm_chart "$chart" ""
            fi
        done

        for binding in $ROLEBINDINGS; do
            if echo "$binding" | grep -q ":"; then
                local binding_name=$(echo "$binding" | cut -d':' -f1)
                local binding_namespaces=$(echo "$binding" | cut -d':' -f2 | tr ',' ' ')

                for ns in $binding_namespaces; do
                    delete_rolebinding "$binding_name" "$ns"
                done
            else
                delete_rolebinding "$binding" ""
            fi
        done

        for role in $ROLES; do
            if echo "$role" | grep -q ":"; then
                local role_name=$(echo "$role" | cut -d':' -f1)
                local role_namespaces=$(echo "$role" | cut -d':' -f2 | tr ',' ' ')

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
        excluded_from_json=$(read_excluded_from_json "$CLUSTER_CONFIG_FILE")
        if [ -n "$excluded_from_json" ]; then
            IFS=',' read -r -a JSON_EXCLUDED <<< "$excluded_from_json"
            for comp in "${JSON_EXCLUDED[@]}"; do
                EXCLUDED_COMPONENTS+=("$(map_component_name "$comp")")
            done
        fi
    fi

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
        for available in ${all_components_array[@]}; do
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
    for comp in ${all_components_array[@]}; do
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