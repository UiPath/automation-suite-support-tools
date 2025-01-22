#!/bin/bash

# Script to configure Istio system permissions
# This script requires 'oc' CLI to be installed and user to be logged in

set -e

# Function to display usage
usage() {
    echo "Usage: $0 -n <namespace> -i <istio-namespace> [-w]"
    echo "  -n    Namespace where uipathadmin service account exists"
    echo "  -i    Istio system namespace"
    echo "  -w    Configure WASM plugin permissions (optional)"
    echo "  -h    Display this help message"
    exit 1
}

# Parse command line arguments
while getopts "n:i:wh" opt; do
    case ${opt} in
        n )
            NAMESPACE=$OPTARG
            ;;
        i )
            ISTIO_NAMESPACE=$OPTARG
            ;;
        w )
            WASM_PLUGIN=true
            ;;
        h )
            usage
            ;;
        \? )
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$NAMESPACE" ] || [ -z "$ISTIO_NAMESPACE" ]; then
    echo "Error: Both namespace (-n) and istio-namespace (-i) are required"
    usage
fi

echo "Configuring Istio permissions:"
echo "Namespace: $NAMESPACE"
echo "Istio Namespace: $ISTIO_NAMESPACE"
echo "WASM Plugin Permissions: ${WASM_PLUGIN:-false}"

# Create temporary directory for YAML files
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Create role for namespace reader
cat > "$TMPDIR/namespace-reader.yaml" << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:  
  name: namespace-reader-clusterrole
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get"]
EOF

# Create Istio system role
if [ "$WASM_PLUGIN" = true ]; then
    # Role with WASM plugin permissions
    cat > "$TMPDIR/istio-role.yaml" << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: istio-system-automationsuite-role
  namespace: $ISTIO_NAMESPACE
rules:
  - apiGroups: [""]
    resources: ["services", "pods"]
    verbs: ["list"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["*"]
  - apiGroups: ["*"]
    resources: ["secrets", "configmaps"]
    verbs: ["get", "watch", "list", "patch", "update", "create"]
  - apiGroups: ["networking.istio.io", "extensions.istio.io"]
    resources: ["*"]
    verbs: ["*"]
EOF
else
    # Role without WASM plugin permissions
    cat > "$TMPDIR/istio-role.yaml" << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: istio-system-automationsuite-role
  namespace: $ISTIO_NAMESPACE
rules:
  - apiGroups: [""]
    resources: ["services", "pods"]
    verbs: ["list"]
  - apiGroups: ["*"]
    resources: ["secrets"]
    resourceNames: ["istio-ingressgateway-certs"]
    verbs: ["get"]
EOF
fi

# Apply the roles
echo "Creating roles..."
oc apply -f "$TMPDIR/namespace-reader.yaml"
oc apply -f "$TMPDIR/istio-role.yaml"

# Create role bindings
echo "Creating role bindings..."
oc project $ISTIO_NAMESPACE
oc create rolebinding istio-system-automationsuite-rolebinding \
  --role=istio-system-automationsuite-role --serviceaccount=$NAMESPACE:uipathadmin

oc create rolebinding namespace-reader-rolebinding \
  --clusterrole=namespace-reader-clusterrole --serviceaccount=$NAMESPACE:uipathadmin

# If WASM plugin is enabled, create additional admin binding
if [ "$WASM_PLUGIN" = true ]; then
    echo "Creating WASM plugin admin binding..."
    oc -n $ISTIO_NAMESPACE create rolebinding uipadmin-istio-system \
      --clusterrole=admin --serviceaccount=$NAMESPACE:uipathadmin
fi

echo "Successfully configured Istio system permissions"
