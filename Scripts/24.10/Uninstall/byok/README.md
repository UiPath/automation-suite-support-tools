This script provides a unified solution for managing UiPath Automation Suite components in both ASEA and OpenShift environments. It allows administrators to selectively delete components while preserving others, making it ideal for cleanup operations and environment management.
Features

    Multi-platform Support: Works with both standard k8s and OpenShift environments

    Component Management: Selectively delete or preserve specific components

    Configuration Options:

        Command-line exclusion lists

        JSON-based configuration file support

        Customizable namespaces for key components

    Safety Features:

        Dry-run mode to preview changes before execution

        Verbose logging for detailed operation tracking

    CRD Instance Cleanup: Automatically handles CRD instances for thorough component removal

Prerequisites

    For ASEA environments: kubectl and helm

    For OpenShift environments: oc and helm

    For JSON configuration parsing: jq (optional, fallback mechanism available)

Installation

Download the script:



Make it executable:

    `chmod +x uninstall.sh`

Usage
`./uninstall.sh [DISTRIBUTION] [OPTIONS]`
Distribution Options

    k8s - Use standard ASEA resources and commands (default)

    openshift - Use OpenShift resources and commands

Command Options

    -h, --help - Display help message and exit

    -d, --dry-run - Perform a dry run (no actual deletion)

    -v, --verbose - Show detailed information during execution

    --excluded COMPONENT1,COMPONENT2 - Components to exclude from deletion (comma-separated)

    --clusterconfig FILE - Path to cluster configuration JSON file with exclude_components array

    --istioNamespace NAMESPACE - Custom namespace for Istio components (default: istio-system)

    --uipathNamespace NAMESPACE - Custom namespace for UiPath components (default: uipath)

    --argocdNamespace NAMESPACE - Custom namespace for ArgoCD components (default: argocd)

Examples
Basic Usage
# Delete all components except istio in k8s
./uninstall.sh k8s --excluded istio

# Delete all components except istio and argocd in OpenShift
./uninstall.sh openshift --excluded istio,argocd
Advanced Usage
# Perform a dry run to see what would be deleted
./uninstall.sh openshift --dry-run

# Load excluded components from a JSON file
./uninstall.sh k8s --clusterconfig cluster_config.json

# Use custom namespaces
./uninstall.sh openshift --uipathNamespace uipath-prod --istioNamespace custom-istio

# Combine multiple options
./uninstall.sh k8s --excluded gatekeeper,falco --clusterconfig input.json --verbose
Available Components

The script can manage the following components:

    istio - Service mesh components

    istio_configure - Istio configuration

    argocd - ArgoCD deployment

    shared_gitops - Shared GitOps (OpenShift only)

    uipath - Core UiPath components

    cert_manager - Certificate management

    network_policies - Network policies

    gatekeeper - Gatekeeper enforcement

    falco - Falco security monitoring

Configuration File Format

The script can read excluded component information from a JSON file (cluster_config.json):
{
"exclude_components": [
"istio",
"argocd",
"gatekeeper"
]
}
Component Dependencies

Some components have dependencies on others. For example:

    If you keep uipath, consider also keeping istio and argocd

    If you keep cert_manager, you typically want to keep uipath

Troubleshooting
Common Issues

Permission Errors: Ensure you have sufficient cluster privileges
# For k8s
kubectl auth can-i delete namespace --all-namespaces

# For OpenShift
oc auth can-i delete project --all-namespaces

Helm Not Found: Verify Helm is installed
helm version

Components Not Deleted: Try running with --verbose for detailed logs

    ./uninstall.sh k8s --verbose

Security Considerations

    Always use --dry-run before performing actual deletions

    Consider backing up critical configurations before running

    When deleting multiple components, be aware of potential dependency issues

Extending the Script
Adding New Components

You can extend the script to manage additional components by following these steps:

    Define the new component in the define_components function:

function define_components {
# Existing components...

    # Add your new component
    my_new_component="
    helm:my-helm-chart:my-namespace
    role:my-role:my-namespace
    rolebinding:my-rolebinding:my-namespace
    namespace:my-namespace
    argocd:my-application
    crd:my.custom.resource
    "
}

Add the component name to the get_all_components function:
function get_all_components {
local components="istio argocd uipath cert_manager network_policies gatekeeper falco istio_configure my_new_component"
# Rest of the function...

    }

    If needed, add any special handling for your component in the script.

Adding New Resource Types

If you need to handle new types of Kubernetes resources:

    Add the new resource type to the parse_component_resources function:

function parse_component_resources {
# Existing variables...
local my_new_resources=""

    while IFS= read -r line || [ -n "$line" ]; do
        # Existing code...
        
        case "$type" in
            # Existing cases...
            
            "my_new_resource_type")
                my_new_resources="$my_new_resources $resource"
                ;;
        esac
    done <<< "$component_def"
    
    # Output existing variables...
    echo "MY_NEW_RESOURCES=\"$my_new_resources\""
}

Create a deletion function for your new resource type:
function delete_my_new_resource_type {
local resource_name=$1

    if $DRY_RUN; then
        echo "DRY-RUN: Would delete my new resource type: $resource_name"
    else
        if $VERBOSE; then
            echo "Deleting my new resource type: $resource_name"
        fi
        $K8S_CMD delete my-custom-resource "$resource_name" --ignore-not-found=true
    }
}

Update the delete_component function to handle your new resource type:
function delete_component {
# Existing code...

    for resource in $MY_NEW_RESOURCES; do
        delete_my_new_resource_type "$resource"
    done
    
    # Rest of the function...

    }

Example: Adding ServiceMonitor Support

Here's a complete example of adding support for Prometheus ServiceMonitors:

    Update parse_component_resources:

function parse_component_resources {
# Add variable
local service_monitors=""

    while IFS= read -r line || [ -n "$line" ]; do
        # Existing code...
        
        case "$type" in
            # Existing cases...
            
            "servicemonitor")
                if echo "$resource" | grep -q ":"; then
                    local monitor_name=$(echo "$resource" | cut -d: -f1)
                    local monitor_ns=$(echo "$resource" | cut -d: -f2)
                    service_monitors="$service_monitors $monitor_name:$monitor_ns"
                else
                    service_monitors="$service_monitors $resource"
                fi
                ;;
        esac
    done <<< "$component_def"
    
    # Add to output
    echo "SERVICE_MONITORS=\"$service_monitors\""
}

Create deletion function:
function delete_service_monitor {
local monitor=$1
local namespace=$2

    if [ -n "$namespace" ]; then
        if $DRY_RUN; then
            echo "DRY-RUN: Would delete ServiceMonitor: $monitor in namespace $namespace"
        else
            if $VERBOSE; then
                echo "Deleting ServiceMonitor: $monitor in namespace $namespace"
            fi
            $K8S_CMD delete servicemonitor "$monitor" -n "$namespace" --ignore-not-found=true
        fi
    else
        # Default namespace handling
        if $DRY_RUN; then
            echo "DRY-RUN: Would delete ServiceMonitor: $monitor in default namespace"
        else
            if $VERBOSE; then
                echo "Deleting ServiceMonitor: $monitor in default namespace"
            fi
            $K8S_CMD delete servicemonitor "$monitor" --ignore-not-found=true
        fi
    fi
}

Update delete_component:
function delete_component {
# Existing code...

    # Process service monitors
    for monitor in $SERVICE_MONITORS; do
        if echo "$monitor" | grep -q ":"; then
            local monitor_name=$(echo "$monitor" | cut -d':' -f1)
            local monitor_ns=$(echo "$monitor" | cut -d':' -f2)
            delete_service_monitor "$monitor_name" "$monitor_ns"
        else
            delete_service_monitor "$monitor" ""
        fi
    done
    
    # Rest of the function...
}

Use in a component definition:
monitoring="
helm:prometheus:monitoring
servicemonitor:uipath-metrics:uipath
servicemonitor:istio-metrics:istio-system
namespace:monitoring

    "

