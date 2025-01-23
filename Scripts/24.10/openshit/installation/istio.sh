#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to create temporary YAML files
create_yaml_files() {
    local temp_dir="$1"
    local min_protocol_version="$2"
    
    # Create Service Mesh Control Plane YAML
    cat > "$temp_dir/servicemesh.yaml" << 'EOL'
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  name: basic
spec:
  gateways:
    enabled: true
    openshiftRoute:
      enabled: true
  addons:
    grafana:
      enabled: true
    jaeger:
      install:
        storage:
          type: Memory
    kiali:
      enabled: true
    prometheus:
      enabled: true
  mode: ClusterWide
  policy:
    type: Istiod
  profiles:
    - default
  telemetry:
    type: Istiod
  tracing:
    sampling: 10000
    type: Jaeger
  version: v2.5
EOL

    # Add TLS min protocol version if specified
    if [ -n "$min_protocol_version" ]; then
        # Create a temporary file with the security section
        cat >> "$temp_dir/servicemesh.yaml" << EOL
  security:
    controlPlane:
      tls:
        minProtocolVersion: $min_protocol_version
EOL
    fi

    # Create Operators YAML
    cat > "$temp_dir/operators.yaml" << 'EOL'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kiali-ossm
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: kiali-ossm
  source: redhat-operators
  sourceNamespace: openshift-marketplace
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: jaeger-product
  namespace: openshift-distributed-tracing
spec:
  channel: stable
  installPlanApproval: Automatic
  name: jaeger-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: servicemeshoperator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
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

# Function to wait for operator deployment
wait_for_operators() {
    local namespace="$1"
    local max_attempts=30
    local sleep_duration=10
    
    local deployments=("kiali-operator" "istio-operator" "jaeger-operator")
    local namespaces=("openshift-operators" "openshift-operators" "openshift-distributed-tracing")
    
    for ((i = 1; i <= max_attempts; i++)); do
        local all_synced=1
        
        for ((j = 0; j < ${#deployments[@]}; j++)); do
            local deployment="${deployments[$j]}"
            local operator_namespace="${namespaces[$j]}"
            
            echo "Checking rollout status of $deployment in namespace $operator_namespace..."
            if ! kubectl rollout status deployment/$deployment -n $operator_namespace; then
                all_synced=0
                break
            fi
        done
        
        if [ "$all_synced" -eq 1 ]; then
            echo "All operators are successfully deployed"
            return 0
        fi
        
        if [ "$i" -lt "$max_attempts" ]; then
            echo "Waiting for operators to be ready..."
            sleep "$sleep_duration"
        else
            echo "Timeout waiting for operators"
            return 1
        fi
    done
}

# Function to wait for Service Mesh Control Plane
wait_for_smcp() {
    local namespace="$1"
    local max_attempts=30
    local sleep_duration=10
    
    for ((i = 1; i <= max_attempts; i++)); do
        local status
        status=$(kubectl get smcp -n "$namespace" | awk 'NR==2{print $3}')
        
        if [ "$status" = "ComponentsReady" ]; then
            echo "Service Mesh Control Plane is ready"
            return 0
        fi
        
        if [ "$i" -lt "$max_attempts" ]; then
            echo "Waiting for Service Mesh Control Plane... Current status: $status"
            sleep "$sleep_duration"
        else
            echo "Timeout waiting for Service Mesh Control Plane"
            return 1
        fi
    done
}

# Main installation function
install_istio() {
    local namespace="$1"
    local min_protocol_version="$2"
    local temp_dir
    
    # Create temporary directory for YAML files
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT
    
    # Create YAML files
    create_yaml_files "$temp_dir" "$min_protocol_version"
    
    # Create required namespaces
    echo "Creating/verifying namespaces..."
    kubectl get namespace "$namespace" >/dev/null 2>&1 || kubectl create namespace "$namespace"
    kubectl get namespace openshift-distributed-tracing >/dev/null 2>&1 || kubectl create namespace openshift-distributed-tracing
    
    # Deploy operators
    echo "Deploying operators..."
    kubectl apply -f "$temp_dir/operators.yaml"
    
    # Wait for operators
    if ! wait_for_operators "$namespace"; then
        echo "Failed to deploy operators"
        return 1
    fi
    
    # Deploy Service Mesh Control Plane
    echo "Deploying Service Mesh Control Plane..."
    kubectl apply -f "$temp_dir/servicemesh.yaml" -n "$namespace"
    
    # Wait for Service Mesh Control Plane
    if ! wait_for_smcp "$namespace"; then
        echo "Failed to deploy Service Mesh Control Plane"
        return 1
    fi
    
    echo "Istio Service Mesh installation completed successfully!"
    return 0
}

# Main script execution
main() {
    echo "Istio Service Mesh Installation Script"
    echo "====================================="
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Get namespace from user
    read -p "Enter namespace for Istio installation [istio-system]: " namespace
    namespace=${namespace:-istio-system}
    
    # Get TLS minimum protocol version
    read -p "Enter minimum TLS protocol version (e.g., TLSv1_2) [press Enter to skip]: " min_protocol_version
    
    # Run installation
    if install_istio "$namespace" "$min_protocol_version"; then
        echo "Installation completed successfully!"
    else
        echo "Installation failed!"
        exit 1
    fi
}

# Execute main function
main
