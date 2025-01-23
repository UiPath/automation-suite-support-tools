#!/bin/bash

set -e

# Constants
MAX_ATTEMPTS=30
SLEEP_DURATION=10

# Print script usage
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
  -t, --instance-type    Instance type (dedicated/shared)
  -n, --namespace        ArgoCD namespace (default: argocd for dedicated, openshift-gitops for shared)
  -u, --uipath-ns        UiPath namespace (default: uipath)
  -c, --cluster-wide     Enable cluster-wide mode (true/false)
  -r, --repo-url         Repository URL
  -U, --repo-user        Repository username
  -P, --repo-pass        Repository password
  -N, --repo-name        Repository name (default: same as repo URL)
  -i, --interactive      Run in interactive mode
  -h, --help            Show this help message

Examples:
  # Interactive mode:
  $0 -i

  # Full CLI mode for dedicated instance:
  $0 \\
    --instance-type dedicated \\
    --namespace argocd \\
    --uipath-ns uipath \\
    --cluster-wide true \\
    --repo-url sfbrdevhelmweacr.azurecr.io \\
    --repo-user sfbrdevhelmweacrreadonly \\
    --repo-pass "yourpassword" \\
    --repo-name "my-repo"
EOF
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    kubectl get "$resource_type" "$resource_name" -n "$namespace" >/dev/null 2>&1
}

# Function to wait for argocd operator deployment
wait_for_operator() {
    local namespace="$1"
    echo "Waiting for ArgoCD operator deployment..."

    local deployments=("openshift-gitops-operator")

    for deploy in "${deployments[@]}"; do
        for ((i = 1; i <= MAX_ATTEMPTS; i++)); do
            if kubectl rollout status deployment/"$deploy" -n "$namespace" >/dev/null 2>&1; then
                echo "Deployment $deploy is ready"
                break
            fi
            if [ $i -eq $MAX_ATTEMPTS ]; then
                echo "ERROR: Timeout waiting for deployment $deploy"
                return 1
            fi
            echo "Waiting for deployment $deploy... Attempt $i/$MAX_ATTEMPTS"
            sleep $SLEEP_DURATION
        done
    done
}

# Function to wait for ArgoCD instance
wait_for_argocd_instance() {
    local namespace="$1"
    local instance_type="$2"
    echo "Waiting for ArgoCD instance to be ready..."

    local deployments=()
    if [ "$instance_type" = "dedicated" ]; then
        deployments=("argocd-server" "argocd-repo-server" "argocd-redis" "argocd-application-controller")
    else
        deployments=("openshift-gitops-server" "openshift-gitops-repo-server" "openshift-gitops-redis" "openshift-gitops-application-controller")
    fi

    for deploy in "${deployments[@]}"; do
        for ((i = 1; i <= MAX_ATTEMPTS; i++)); do
            if kubectl rollout status deployment/"$deploy" -n "$namespace" >/dev/null 2>&1; then
                echo "Deployment $deploy is ready"
                break
            fi
            if [ $i -eq $MAX_ATTEMPTS ]; then
                echo "ERROR: Timeout waiting for deployment $deploy"
                return 1
            fi
            echo "Waiting for deployment $deploy... Attempt $i/$MAX_ATTEMPTS"
            sleep $SLEEP_DURATION
        done
    done
}

# Function to create YAML files
create_yaml_files() {
    local temp_dir="$1"
    local namespace="$2"
    local uipath_namespace="$3"
    local instance_type="$4"

    # Create Operator YAML
    cat > "$temp_dir/argo-operators.yaml" << EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  config:
    tolerations:
      - effect: NoSchedule
        operator: Exists
        key: node-role.kubernetes.io/master
      - effect: NoSchedule
        operator: Exists
        key: uipath
EOF

    # Create ArgoCD Instance YAML
    cat > "$temp_dir/argocd.yaml" << EOF
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: argocd
spec:
  server:
    autoscale:
      enabled: false
    grpc:
      ingress:
        enabled: false
    ingress:
      enabled: false
    route:
      enabled: true
    service:
      type: ''
  grafana:
    enabled: false
  prometheus:
    enabled: false
  notifications:
    enabled: false
  initialSSHKnownHosts: {}
  rbac: {}
  repo: {}
  ha:
    enabled: false
  tls:
    ca: {}
  redis: {}
EOF

    # Create role configurations
    cat > "$temp_dir/roles.yaml" << EOF
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: limit-range-manager
  namespace: $uipath_namespace
rules:
  - apiGroups: ["*"]
    resources: ["limitranges"]
    verbs: ["get", "watch", "list", "patch", "update", "create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: uipath-application-manager
  namespace: $namespace
rules:
- apiGroups:
  - argoproj.io
  resources:
  - applications
  verbs:
  - "*"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argo-secret-role
  namespace: $namespace
rules:
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["*"]
  - apiGroups: ["*"]
    resources: ["secrets"]
    verbs: ["get", "watch", "list", "patch", "update", "create"]
EOF
}

# Function to configure ArgoCD instance
configure_argocd_instance() {
    local namespace="$1"
    local temp_dir="$2"

    echo "Configuring ArgoCD instance..."
    kubectl apply -f "$temp_dir/argocd.yaml" -n "$namespace"

    if ! wait_for_argocd_instance "$namespace" "dedicated"; then
        echo "ERROR: Failed to configure ArgoCD instance"
        return 1
    fi
}

label_namespace() {
    local namespace="$1"
    local argocd_namespace="$2"

    echo "Labeling namespace $namespace for ArgoCD management..."
    kubectl label namespace "$namespace" argocd.argoproj.io/managed-by="$argocd_namespace" --overwrite
    kubectl label namespace "$namespace" argo_namespace="$argocd_namespace" --overwrite
}

create_subscription_patch() {
    local temp_dir="$1"
    local argocd_namespace="$2"

    # Create subscription patch file
    cat > "$temp_dir/argo-subscription-patch.yaml" << EOF
spec:
  config:
    env:
    - name: ARGOCD_CLUSTER_CONFIG_NAMESPACES
      value: ${argocd_namespace}
EOF

    # Apply patch
    kubectl patch subscription openshift-gitops-operator \
        -n openshift-gitops-operator \
        --patch "$(cat $temp_dir/argo-subscription-patch.yaml)" \
        --type=merge
}

# Function to install ArgoCD CLI
install_argocd_cli() {
    echo "Checking ArgoCD CLI installation..."

    if command_exists argocd; then
        echo "INFO: ArgoCD CLI is already installed"
        return 0
    fi

    echo "Installing ArgoCD CLI..."
    VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

    case "$(uname -s)" in
        Linux*)
            sudo curl -sSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64"
            sudo chmod +x /usr/local/bin/argocd
            ;;
        Darwin*)
            if command_exists brew; then
                brew install argocd
            else
                echo "ERROR: Homebrew not found. Please install Homebrew or manually install ArgoCD CLI"
                return 1
            fi
            ;;
        *)
            echo "ERROR: Unsupported operating system. Please install ArgoCD CLI manually"
            return 1
            ;;
    esac

    if command_exists argocd; then
        echo "INFO: ArgoCD CLI installed successfully"
        return 0
    else
        echo "ERROR: Failed to install ArgoCD CLI"
        return 1
    fi
}

# Function to configure repository
configure_repository() {
    local namespace="$1"
    local repo_url="$2"
    local repo_username="$3"
    local repo_password="$4"
    local repo_name="$5"

    echo "Configuring repository..."

    # Install ArgoCD CLI if needed
    if ! command_exists argocd; then
        if ! install_argocd_cli; then
            echo "ERROR: Failed to install ArgoCD CLI"
            return 1
        fi
    fi

    # Wait for ArgoCD route to be available
    local argo_route=""
    for ((i = 1; i <= MAX_ATTEMPTS; i++)); do
        argo_route=$(kubectl get routes argocd-server -n "$namespace" -o jsonpath='{.spec.host}' 2>/dev/null)
        if [ -n "$argo_route" ]; then
            break
        fi
        if [ $i -eq $MAX_ATTEMPTS ]; then
            echo "ERROR: Timeout waiting for ArgoCD route"
            return 1
        fi
        echo "Waiting for ArgoCD route... Attempt $i/$MAX_ATTEMPTS"
        sleep $SLEEP_DURATION
    done

    local argo_url="https://$argo_route"
    local argo_password=$(kubectl -n "$namespace" get secrets argocd-cluster -o jsonpath='{.data.admin\.password}' | base64 -d)
    local argo_username="admin"

    # Login to ArgoCD
    if ! argocd login "${argo_url}" --password "${argo_password}" --username "$argo_username" --insecure --grpc-web --grpc-web-root-path "/"; then
        echo "ERROR: Failed to log in to ArgoCD"
        return 1
    fi

    # Add repository
    if ! argocd repo add "$repo_url" \
        --username "$repo_username" \
        --password "$repo_password" \
        --enable-oci \
        --type helm \
        --name "$repo_name"; then
        echo "ERROR: Failed to add repository"
        return 1
    fi

    echo "Repository configured successfully!"
}

configure_cluster_wide() {
    local namespace="$1"
    local temp_dir="$2"

    echo "Enabling cluster-wide mode for ArgoCD..."
    if ! create_subscription_patch "$temp_dir" "$namespace"; then
        echo "ERROR: Failed to configure cluster-wide mode"
        return 1
    fi

    # Wait for the subscription update to take effect
    sleep $SLEEP_DURATION
    return 0
}

# Main installation function
install_argocd() {
    local instance_type="$1"
    local namespace="$2"
    local uipath_namespace="$3"
    local cluster_wide="$4"
    local repo_url="$5"
    local repo_username="$6"
    local repo_password="$7"
    local repo_name="$8"

    echo "Starting ArgoCD installation..."

    # Create temporary directory
    local temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    # Create YAML files
    create_yaml_files "$temp_dir" "$namespace" "$uipath_namespace" "$instance_type"

    # Create namespaces
    kubectl create namespace "$namespace" 2>/dev/null || true
    kubectl create namespace "$uipath_namespace" 2>/dev/null || true
    kubectl create namespace "openshift-gitops-operator" 2>/dev/null || true

    # Label namespaces
    label_namespace "$uipath_namespace" "$namespace"

    # Install operator
    echo "Installing ArgoCD operator..."
    kubectl apply -f "$temp_dir/argo-operators.yaml"

    # Configure cluster-wide mode if requested
    if [ "$cluster_wide" = "true" ]; then
        if ! configure_cluster_wide "$namespace" "$temp_dir"; then
            echo "ERROR: Failed to configure cluster-wide mode"
            return 1
        fi
    fi

    if ! wait_for_operator "openshift-gitops-operator"; then
        echo "ERROR: Failed to install operator"
        return 1
    fi

    # Configure ArgoCD instance
    if [ "$instance_type" = "dedicated" ]; then
        if ! configure_argocd_instance "$namespace" "$temp_dir"; then
            return 1
        fi
    fi

    # Apply roles
    echo "Applying roles and bindings..."
    kubectl apply -f "$temp_dir/roles.yaml"

    # Configure repository if details provided
    if [ -n "$repo_url" ]; then
        if ! configure_repository "$namespace" "$repo_url" "$repo_username" "$repo_password" "$repo_name"; then
            return 1
        fi
    fi

    echo "ArgoCD installation completed successfully!"
    return 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--instance-type)
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -u|--uipath-ns)
                UIPATH_NAMESPACE="$2"
                shift 2
                ;;
            -c|--cluster-wide)
                CLUSTER_WIDE="$2"
                shift 2
                ;;
            -r|--repo-url)
                REPO_URL="$2"
                shift 2
                ;;
            -U|--repo-user)
                REPO_USERNAME="$2"
                shift 2
                ;;
            -P|--repo-pass)
                REPO_PASSWORD="$2"
                shift 2
                ;;
            -N|--repo-name)
                REPO_NAME="$2"
                shift 2
                ;;
            -i|--interactive)
                INTERACTIVE=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

# Main script execution
main() {
    parse_args "$@"

    # Set defaults if not provided
    INSTANCE_TYPE=${INSTANCE_TYPE:-dedicated}
    NAMESPACE=${NAMESPACE:-${INSTANCE_TYPE == "dedicated" ? "argocd" : "openshift-gitops"}}
    UIPATH_NAMESPACE=${UIPATH_NAMESPACE:-uipath}
    CLUSTER_WIDE=${CLUSTER_WIDE:-false}
    REPO_NAME=${REPO_NAME:-$REPO_URL}

    # Run installation
    if ! install_argocd "$INSTANCE_TYPE" "$NAMESPACE" "$UIPATH_NAMESPACE" "$CLUSTER_WIDE" \
        "$REPO_URL" "$REPO_USERNAME" "$REPO_PASSWORD" "$REPO_NAME"; then
        echo "ERROR: Installation failed"
        exit 1
    fi

    # Print access information
    echo -e "\nArgoCD Access Information:"
    echo "=========================="
    local server_route
    if [ "$INSTANCE_TYPE" = "dedicated" ]; then
        server_route="argocd-server"
    else
        server_route="openshift-gitops-server"
    fi

    local argo_url=$(kubectl get routes "$server_route" -n "$NAMESPACE" -o jsonpath={.spec.host})
    local argo_password=$(kubectl -n "$NAMESPACE" get secrets argocd-cluster -o jsonpath='{.data.admin\.password}' | base64 -d)

    echo "URL: https://$argo_url"
    echo "Username: admin"
    echo "Password: $argo_password"

    echo -e "\nNext Steps:"
    echo "1. Access the ArgoCD UI using the credentials above"
    if [ -z "$REPO_URL" ]; then
        echo "2. To configure a repository later, you can:"
        echo "   a) Use the ArgoCD CLI:"
        echo "      argocd login $argo_url --username admin --password $argo_password --insecure"
        echo "      argocd repo add <repo-url> --username <username> --password <password> --type helm --name <name>"
        echo "   b) Use the ArgoCD UI:"
        echo "      - Go to Settings > Repositories"
        echo "      - Click '+CONNECT REPO'"
        echo "      - Configure your repository details"
    fi
    echo "3. For cluster-scoped resources management:"
    echo "   - Verify cluster role bindings"
    echo "   - Check namespace labels"
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi