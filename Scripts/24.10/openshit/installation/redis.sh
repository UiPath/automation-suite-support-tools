#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to create temporary YAML files
create_yaml_files() {
    local temp_dir="$1"

    # Create SCC YAML
    cat > "$temp_dir/scc.yaml" << 'EOL'
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: redis-enterprise-scc-v2
  annotations:
    kubernetes.io/description: redis-enterprise-scc is the minimal SCC needed to run Redis Enterprise nodes on Kubernetes.
allowedCapabilities:
  - SYS_RESOURCE
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: false
allowPrivilegedContainer: false
readOnlyRootFilesystem: false
runAsUser:
  type: MustRunAs
  uid: 1001
fsGroup:
  type: MustRunAs
  ranges:
    - min: 1001
      max: 1001
seLinuxContext:
  type: MustRunAs
seccompProfiles:
  - runtime/default
supplementalGroups:
  type: RunAsAny
EOL

    # Create Operators YAML
    cat > "$temp_dir/redis-operators.yaml" << 'EOL'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  annotations:
    olm.providedAPIs: RedisEnterpriseActiveActiveDatabase.v1alpha1.app.redislabs.com,RedisEnterpriseCluster.v1.app.redislabs.com,RedisEnterpriseDatabase.v1alpha1.app.redislabs.com,RedisEnterpriseRemoteCluster.v1alpha1.app.redislabs.com
  name: redis-operatorgroup
spec:
  targetNamespaces:
    - redis-system
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: redis-enterprise-operator-cert
spec:
  channel: production
  installPlanApproval: Automatic
  name: redis-enterprise-operator-cert
  source: certified-operators
  sourceNamespace: openshift-marketplace
  config:
    tolerations:
      - effect: NoSchedule
        operator: Exists
        key: node-role.kubernetes.io/master
      - effect: NoSchedule
        operator: Exists
        key: uipath
EOL

    # Create Redis Enterprise Cluster YAML
    cat > "$temp_dir/redis-enterprise-cluster.yaml" << 'EOL'
apiVersion: app.redislabs.com/v1
kind: RedisEnterpriseCluster
metadata:
  name: rec
spec:
  bootstrapperImageSpec:
    repository: registry.connect.redhat.com/redislabs/redis-enterprise-operator
  persistentSpec:
    enabled: true
  redisEnterpriseServicesRiggerImageSpec:
    repository: registry.connect.redhat.com/redislabs/services-manager
  redisEnterpriseImageSpec:
    imagePullPolicy: IfNotPresent
    repository: registry.connect.redhat.com/redislabs/redis-enterprise
  nodes: 1
  uiServiceType: ClusterIP
EOL

    # Create Redis Database YAML
    cat > "$temp_dir/redis-database.yaml" << 'EOL'
apiVersion: app.redislabs.com/v1alpha1
kind: RedisEnterpriseDatabase
metadata:
  name: redb
spec:
  tlsMode: disabled
  databasePort: 6380
EOL
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()

    if ! command_exists kubectl && ! command_exists oc; then
        missing_tools+=("kubectl/oc")
    fi

    if ! command_exists jq; then
        missing_tools+=("jq")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "Error: The following required tools are missing:"
        printf '%s\n' "${missing_tools[@]}"
        echo "Please install them and try again."
        return 1
    fi

    return 0
}

# Main installation function
install_redis() {
    local namespace="$1"
    local install_operator="$2"
    local temp_dir

    # Create temporary directory for YAML files
    temp_dir=$(mktemp -d)
    echo "Temp Directory: $temp_dir"

    # Create YAML files
    create_yaml_files "$temp_dir"

    # Create namespace if it doesn't exist
    if kubectl get namespace "$namespace" >/dev/null 2>&1; then
        echo "Using existing namespace: $namespace"
    else
        echo "Creating namespace: $namespace"
        kubectl create namespace "$namespace"
    fi

    # Apply SCC
    echo "Applying Security Context Constraints..."
    kubectl apply -f "$temp_dir/scc.yaml" -n "$namespace"

    # Install operator if requested
    if [ "$install_operator" = "y" ]; then
        echo "Installing Redis Enterprise Operator..."
        kubectl apply -f "$temp_dir/redis-operators.yaml" -n "$namespace"

        echo "Waiting for operator deployment to complete..."
        kubectl rollout status deployment/redis-enterprise-operator -n "$namespace" --timeout=300s || {
            echo "Redis Enterprise Operator deployment failed"
            return 1
        }
    fi

    # Deploy Redis Enterprise Cluster
    echo "Deploying Redis Enterprise Cluster..."
    kubectl apply -f "$temp_dir/redis-enterprise-cluster.yaml" -n "$namespace"

    # Wait for cluster to be ready
    echo "Waiting for Redis Enterprise Cluster to be ready..."
    for i in {1..30}; do
        echo "Waiting for Redis Enterprise Cluster to be ready...$i/30"
        if [ "$(kubectl get RedisEnterpriseCluster -n "$namespace" -o json | jq -r '.items[0].status.state')" = "Running" ]; then
            break
        fi
        if [ "$i" = "30" ]; then
            echo "Redis Enterprise Cluster deployment failed"
            return 1
        fi
        sleep 10
    done

    # Deploy Redis Database
    echo "Deploying Redis Database..."
    kubectl apply -f "$temp_dir/redis-database.yaml" -n "$namespace"

    # Wait for database to be ready
    echo "Waiting for Redis Database to be ready..."
    for i in {1..30}; do
        if [ "$(kubectl get redisenterprisedatabase -n "$namespace" -o json | jq -r '.items[0].status.status')" = "active" ]; then
            break
        fi
        if [ "$i" = "30" ]; then
            echo "Redis Database deployment failed"
            return 1
        fi
        sleep 10
    done

    echo "Redis Enterprise installation completed successfully!"
    return 0
}

# Main script execution
main() {
    echo "Redis Enterprise Installation Script"
    echo "==================================="

    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi

    # Get namespace from user
    read -p "Enter namespace for Redis installation [redis-system]: " namespace
    namespace=${namespace:-redis-system}

    # Ask about operator installation
    while true; do
        read -p "Do you want to install the Redis Enterprise Operator? (y/n): " install_operator
        case $install_operator in
            [Yy]* ) install_operator="y"; break;;
            [Nn]* ) install_operator="n"; break;;
            * ) echo "Please answer y or n.";;
        esac
    done

    # Run installation
    if install_redis "$namespace" "$install_operator"; then
        echo "Installation completed successfully!"
    else
        echo "Installation failed!"
        exit 1
    fi
}

# Execute main function
main