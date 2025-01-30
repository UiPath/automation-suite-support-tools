#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to create temporary YAML files
create_yaml_files() {
    local temp_dir="$1"
    
    # Create Operator Group and Subscription YAML
    cat > "$temp_dir/cert-manager-operator.yaml" << 'EOL'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-cert-manager-operator
  namespace: cert-manager-operator
spec:
  targetNamespaces:
    - "cert-manager-operator"
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-cert-manager-operator
  namespace: cert-manager-operator
spec:
  channel: stable-v1
  name: openshift-cert-manager-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
  config:
    tolerations:
      - effect: NoSchedule
        operator: Exists
        key: node-role.kubernetes.io/master
      - effect: NoSchedule
        operator: Exists
        key: uipath
EOL
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    if ! command_exists kubectl && ! command_exists oc; then
        missing_tools+=("kubectl/oc")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "Error: The following required tools are missing:"
        printf '%s\n' "${missing_tools[@]}"
        echo "Please install them and try again."
        return 1
    fi

    return 0
}

# Function to verify paths
verify_paths() {
    local config_dir="$1"
    local required_files=(
        "operators/cert-manager-operator.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "${config_dir}/${file}" ]; then
            echo "Error: Required file ${config_dir}/${file} not found"
            return 1
        fi
    done
    return 0
}

# Function to wait for deployments
wait_for_deployments() {
    local namespace="cert-manager"
    local max_attempts=30
    local sleep_duration=10
    local deployments=("cert-manager" "cert-manager-webhook" "cert-manager-cainjector")
    
    for ((i = 1; i <= max_attempts; i++)); do
        local all_synced=1
        
        for deployment in "${deployments[@]}"; do
            echo "Checking rollout status of $deployment in namespace $namespace..."
            if ! kubectl rollout status deployment/$deployment -n $namespace; then
                all_synced=0
                break
            fi
        done
        
        if [ "$all_synced" -eq 1 ]; then
            echo "All deployments are successfully rolled out"
            return 0
        fi
        
        if [ "$i" -lt "$max_attempts" ]; then
            echo "Waiting for deployments to be ready..."
            sleep "$sleep_duration"
        else
            echo "Timeout waiting for deployments"
            return 1
        fi
    done
}

# Main installation function
install_cert_manager() {
    local config_dir="$1"
    local temp_dir
    
    # Create temporary directory for YAML files
    temp_dir=$(mktemp -d)
    echo "Temp Directory: $temp_dir"
    
    # Create YAML files
    create_yaml_files "$temp_dir"
    
    # Create operator namespace
    echo "Creating/verifying operator namespace..."
    kubectl get namespace cert-manager-operator >/dev/null 2>&1 || kubectl create namespace cert-manager-operator
    
    # Deploy operator
    echo "Deploying Cert-Manager operator..."
    if [ -f "${config_dir}/operators/cert-manager-operator.yaml" ]; then
        kubectl apply -f "${config_dir}/operators/cert-manager-operator.yaml"
    else
        kubectl apply -f "$temp_dir/cert-manager-operator.yaml"
    fi
    
    # Wait for deployments
    echo "Waiting for Cert-Manager deployments..."
    if ! wait_for_deployments; then
        echo "Failed to deploy Cert-Manager"
        return 1
    fi
    
    echo "Cert-Manager installation completed successfully!"
    return 0
}

# Main script execution
main() {
    echo "Cert-Manager Installation Script"
    echo "==============================="
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Get configuration directory path
    echo "Enter path to configuration directory where resources/ and operators/ folders are located"
    read -p "[./kubernetes]: " config_dir
    config_dir=${config_dir:-"./kubernetes"}
    
    # Verify paths if using external files
    if [ -d "$config_dir" ]; then
        verify_paths "$config_dir" || {
            echo "Warning: Some configuration files are missing, will use embedded configurations."
        }
    else
        echo "Warning: Configuration directory not found, will use embedded configurations."
    fi
    
    # Run installation
    if install_cert_manager "$config_dir"; then
        echo "Installation completed successfully!"
        echo -e "\nTo verify the installation:"
        echo "1. Check deployments: kubectl get deployments -n cert-manager"
        echo "2. Check pods: kubectl get pods -n cert-manager"
    else
        echo "Installation failed!"
        exit 1
    fi
}

# Execute main function
main
