#!/bin/bash

# uipath-k8s-component-manager.sh
# Script to manage UiPath Automation Suite Kubernetes components
# Deletes all components except those specified in the arguments

# Exit on any error
set -e

# Display help message
function show_help {
    echo "Usage: $0 [OPTIONS] [COMPONENT_NAMES]"
    echo
    echo "Deletes all UiPath Automation Suite Kubernetes components except those specified in the arguments."
    echo
    echo "Options:"
    echo "  -h, --help     Display this help message and exit"
    echo "  -d, --dry-run  Perform a dry run (no actual deletion)"
    echo "  -v, --verbose  Show detailed information during execution"
    echo
    echo "Examples:"
    echo "  $0 istio argocd        # Keep istio and argocd components, delete all others"
    echo "  $0 --dry-run           # Show what would be deleted without actually deleting"
    echo
    echo "Available components:"
    get_all_components | tr ' ' '\n' | sort | sed 's/^/  - /'
    echo
}

# Check prerequisites
function check_prerequisites {
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl is not installed or not in PATH"
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        echo "Error: helm is not installed or not in PATH"
        exit 1
    fi
}

# Component definitions
# Format for resources:
# - Helm charts: helm:chart_name or helm:chart_name:namespace
# - Roles: role:role_name or role:role_name:namespace1,namespace2
# - Rolebindings: rolebinding:rolebinding_name or rolebinding:rolebinding_name:namespace1,namespace2
# - ArgoCD applications: argocd:app_name
# - Namespaces: namespace:namespace_name
function define_components {
    # Istio component
    istio="
    helm:istio-base:istio-system
    helm:istio:istio-system
    helm:istio-ingressgateway:istio-system
    helm:istio-configure:istio-system
    role:istio-system-automationsuite-role:istio-system
    rolebinding:istio-system-automationsuite-rolebinding:istio-system
    rolebinding:uipadmin-istio-system:istio-system
    namespace:istio-system
    "

    # ArgoCD component
    argocd="
    helm:argocd:argocd
    role:argo-secret-role:argocd
    role:uipath-application-manager:argocd
    rolebinding:secret-binding:argocd
    rolebinding:uipath-application-manager-rolebinding:argocd
    rolebinding:namespace-reader-rolebinding:argocd
    argocd:dapr
    namespace:argocd
    "

    # UiPath component
 uipath="
    helm:uipath-orchestrator:uipath
    helm:uipath-identity-service:uipath
    helm:uipath-automation-suite:uipath
    role:uipath-role
    role:uipath-admin-role:default,uipath
    role:uipath-automationsuite-role:uipath
    role:uipath-viewer-role:uipath
    rolebinding:uipath-rolebinding
    rolebinding:uipath-admin-rolebinding:default,uipath
    rolebinding:uipath-automationsuite-rolebinding:uipath
    rolebinding:uipath-viewer-rolebinding:uipath
    rolebinding:uipathadmin:uipath
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
    argocd:dapr
    argocd:datapipeline-api
    argocd:dataservice
    argocd:documentunderstanding
    argocd:insights
    argocd:integrationservices
    argocd:notificationservice
    argocd:network-policies
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
    namespace:uipath
    "

    # Cert-manager component (required for Process Mining)
    cert_manager="
    helm:cert-manager:cert-manager
    role:cert-manager-role:cert-manager
    rolebinding:cert-manager-rolebinding:cert-manager
    namespace:cert-manager
    "

    # Dapr component (required for Process Mining)
    dapr="
    helm:dapr:uipath
    role:dapr-role:uipath
    rolebinding:dapr-rolebinding:uipath
    argocd:dapr
    "

    # Authentication component
    authentication="
    helm:keycloak:uipath
    role:keycloak-role:uipath
    rolebinding:keycloak-rolebinding:uipath
    "

    # Cluster roles and permissions
    cluster_permissions="
    role:namespace-reader-clusterrole
    role:list-nodes-and-crd-clusterrole
    role:storage-class-reader
    rolebinding:namespace-reader-rolebinding
    rolebinding:list-nodes-and-crd-rolebinding
    rolebinding:storage-class-reader-binding
    "

    # Priority classes
    priority_classes="
    priorityclass:uipath-high-priority
    "
}

# Get all component names
function get_all_components {
    define_components
    # Use hardcoded list instead of checking all environment variables
    echo "istio argocd uipath cert_manager dapr authentication cluster_permissions priority_classes"
}

# Parse a component's resources
function parse_component_resources {
    local component_def="$1"
    local helm_charts=""
    local namespaces=""
    local roles=""
    local rolebindings=""
    local argocd_apps=""
    local priority_classes=""

    # Read line by line
    while read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue

        # Trim whitespace
        line=$(echo "$line" | xargs)

        # Skip if still empty after trimming
        [ -z "$line" ] && continue

        # Split by colon to get type and resource
        local type=$(echo "$line" | cut -d: -f1)
        local resource=$(echo "$line" | cut -d: -f2-)

        case "$type" in
            "helm")
                # Check if resource has namespace
                if [[ "$resource" == *":"* ]]; then
                    local res_name=$(echo "$resource" | cut -d: -f1)
                    local res_ns=$(echo "$resource" | cut -d: -f2)
                    helm_charts="$helm_charts $res_name:$res_ns"
                    # Add namespace if not already in the list
                    if [[ ! "$namespaces" =~ (^|[[:space:]])"$res_ns"($|[[:space:]]) ]]; then
                        namespaces="$namespaces $res_ns"
                    fi
                else
                    helm_charts="$helm_charts $resource"
                fi
                ;;
            "role")
                # Check if role has namespaces
                if [[ "$resource" == *":"* ]]; then
                    local res_name=$(echo "$resource" | cut -d: -f1)
                    local res_ns=$(echo "$resource" | cut -d: -f2)
                    roles="$roles $res_name:$res_ns"
                    # Add namespaces if not already in the list
                    IFS=',' read -ra NS_ARRAY <<< "$res_ns"
                    for ns in "${NS_ARRAY[@]}"; do
                        if [[ ! "$namespaces" =~ (^|[[:space:]])"$ns"($|[[:space:]]) ]]; then
                            namespaces="$namespaces $ns"
                        fi
                    done
                else
                    roles="$roles $resource"
                fi
                ;;
            "rolebinding")
                # Check if rolebinding has namespaces
                if [[ "$resource" == *":"* ]]; then
                    local res_name=$(echo "$resource" | cut -d: -f1)
                    local res_ns=$(echo "$resource" | cut -d: -f2)
                    rolebindings="$rolebindings $res_name:$res_ns"
                    # Add namespaces if not already in the list
                    IFS=',' read -ra NS_ARRAY <<< "$res_ns"
                    for ns in "${NS_ARRAY[@]}"; do
                        if [[ ! "$namespaces" =~ (^|[[:space:]])"$ns"($|[[:space:]]) ]]; then
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
                if [[ ! "$namespaces" =~ (^|[[:space:]])"$resource"($|[[:space:]]) ]]; then
                    namespaces="$namespaces $resource"
                fi
                ;;
            "priorityclass")
                priority_classes="$priority_classes $resource"
                ;;
        esac
    done <<< "$component_def"

    # Trim leading/trailing spaces
    helm_charts=$(echo "$helm_charts" | xargs)
    namespaces=$(echo "$namespaces" | xargs)
    roles=$(echo "$roles" | xargs)
    rolebindings=$(echo "$rolebindings" | xargs)
    argocd_apps=$(echo "$argocd_apps" | xargs)
    priority_classes=$(echo "$priority_classes" | xargs)

    echo "HELM_CHARTS=\"$helm_charts\""
    echo "NAMESPACES=\"$namespaces\""
    echo "ROLES=\"$roles\""
    echo "ROLEBINDINGS=\"$rolebindings\""
    echo "ARGOCD_APPS=\"$argocd_apps\""
    echo "PRIORITY_CLASSES=\"$priority_classes\""
}

# Delete a helm chart
function delete_helm_chart {
    local chart=$1
    local namespace=$2

    if [ -n "$namespace" ]; then
        if $dry_run; then
            echo "DRY-RUN: Would uninstall helm chart: $chart in namespace $namespace"
        else
            if $verbose; then
                echo "Uninstalling helm chart: $chart in namespace $namespace"
            fi
            helm uninstall "$chart" -n "$namespace" || echo "Failed to uninstall $chart in $namespace"
        fi
    else
        if $dry_run; then
            echo "DRY-RUN: Would uninstall helm chart: $chart (default namespace)"
        else
            if $verbose; then
                echo "Uninstalling helm chart: $chart (default namespace)"
            fi
            helm uninstall "$chart" || echo "Failed to uninstall $chart"
        fi
    fi
}

# Delete a role
function delete_role {
    local role=$1
    local namespace=$2

    if [ -n "$namespace" ]; then
        if $dry_run; then
            echo "DRY-RUN: Would delete role: $role in namespace $namespace"
        else
            if $verbose; then
                echo "Deleting role: $role in namespace $namespace"
            fi
            kubectl delete role "$role" -n "$namespace" --ignore-not-found=true
        fi
    else
        if $dry_run; then
            echo "DRY-RUN: Would delete clusterrole: $role"
        else
            if $verbose; then
                echo "Deleting clusterrole: $role"
            fi
            kubectl delete clusterrole "$role" --ignore-not-found=true
        fi
    fi
}

# Delete a rolebinding
function delete_rolebinding {
    local rolebinding=$1
    local namespace=$2

    if [ -n "$namespace" ]; then
        if $dry_run; then
            echo "DRY-RUN: Would delete rolebinding: $rolebinding in namespace $namespace"
        else
            if $verbose; then
                echo "Deleting rolebinding: $rolebinding in namespace $namespace"
            fi
            kubectl delete rolebinding "$rolebinding" -n "$namespace" --ignore-not-found=true
        fi
    else
        if $dry_run; then
            echo "DRY-RUN: Would delete clusterrolebinding: $rolebinding"
        else
            if $verbose; then
                echo "Deleting clusterrolebinding: $rolebinding"
            fi
            kubectl delete clusterrolebinding "$rolebinding" --ignore-not-found=true
        fi
    fi
}

# Delete an ArgoCD application
function delete_argocd_app {
    local app=$1

    if $dry_run; then
        echo "DRY-RUN: Would delete ArgoCD application: $app"
    else
        if $verbose; then
            echo "Deleting ArgoCD application: $app"
        fi
        kubectl delete application "$app" -n argocd --ignore-not-found=true
    fi
}

# Delete a namespace
function delete_namespace {
    local namespace=$1

    if $dry_run; then
        echo "DRY-RUN: Would delete namespace: $namespace"
    else
        if $verbose; then
            echo "Deleting namespace: $namespace"
        fi
        kubectl delete namespace "$namespace" --ignore-not-found=true
    fi
}

# Delete a priority class
function delete_priority_class {
    local priority_class=$1

    if $dry_run; then
        echo "DRY-RUN: Would delete priority class: $priority_class"
    else
        if $verbose; then
            echo "Deleting priority class: $priority_class"
        fi
        kubectl delete priorityclass "$priority_class" --ignore-not-found=true
    fi
}

# Process a component for deletion
function delete_component {
    local component_name=$1

    echo "Processing component for deletion: $component_name"

    # Get the component variable value
    local component_def="${!component_name}"

    # Temporary file to hold parsed resources
    local temp_file=$(mktemp)
    parse_component_resources "$component_def" > "$temp_file"
    source "$temp_file"
    rm "$temp_file"

    # Process ArgoCD applications first (to prevent reconciliation)
    for app in $ARGOCD_APPS; do
        delete_argocd_app "$app"
    done

    # Process helm charts
    for chart in $HELM_CHARTS; do
        # Check if chart has namespace specified
        if [[ "$chart" == *":"* ]]; then
            local chart_name=$(echo "$chart" | cut -d':' -f1)
            local chart_ns=$(echo "$chart" | cut -d':' -f2)
            delete_helm_chart "$chart_name" "$chart_ns"
        else
            delete_helm_chart "$chart" ""
        fi
    done

    # Process rolebindings
    for binding in $ROLEBINDINGS; do
        # Check if rolebinding has namespace specified
        if [[ "$binding" == *":"* ]]; then
            local binding_name=$(echo "$binding" | cut -d':' -f1)
            local binding_namespaces=$(echo "$binding" | cut -d':' -f2 | tr ',' ' ')

            for ns in $binding_namespaces; do
                delete_rolebinding "$binding_name" "$ns"
            done
        else
            delete_rolebinding "$binding" ""
        fi
    done

    # Process roles
    for role in $ROLES; do
        # Check if role has namespace specified
        if [[ "$role" == *":"* ]]; then
            local role_name=$(echo "$role" | cut -d':' -f1)
            local role_namespaces=$(echo "$role" | cut -d':' -f2 | tr ',' ' ')

            for ns in $role_namespaces; do
                delete_role "$role_name" "$ns"
            done
        else
            delete_role "$role" ""
        fi
    done

    # Process priority classes
    for pc in $PRIORITY_CLASSES; do
        delete_priority_class "$pc"
    done

    # Process namespaces (delete last to ensure resources are cleaned up first)
    for ns in $NAMESPACES; do
        delete_namespace "$ns"
    done

    echo "Completed processing component: $component_name"
    echo
}

# Main function
function main {
    check_prerequisites

    # Initialize variables
    local dry_run=false
    local verbose=false
    local components_to_keep=()

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            *)
                components_to_keep+=("$1")
                shift
                ;;
        esac
    done

    # Define all components
    define_components

    # Get all available components
    local all_components=($(get_all_components))

    if [ ${#components_to_keep[@]} -eq 0 ]; then
        echo "No components specified to keep. All components will be deleted."
    else
        echo "Components to keep: ${components_to_keep[*]}"
    fi

    # Check if specified components exist
    for comp in "${components_to_keep[@]}"; do
        if ! [[ " ${all_components[*]} " =~ " ${comp} " ]]; then
            echo "Warning: Component '$comp' is not recognized and will be ignored."
        fi
    done

    # Determine components to delete
    local components_to_delete=()
    for comp in "${all_components[@]}"; do
        if ! [[ " ${components_to_keep[*]} " =~ " ${comp} " ]]; then
            components_to_delete+=("$comp")
        fi
    done

    echo "Components to delete: ${components_to_delete[*]}"
    echo

    # Delete components
    for comp in "${components_to_delete[@]}"; do
        delete_component "$comp"
    done

    if $dry_run; then
        echo "Dry run completed. No changes were made."
    else
        echo "All specified components have been deleted."
    fi
}

# Run main function with all arguments
main "$@"