#!/bin/bash

# Script to configure ArgoCD permissions
# This script requires 'oc' CLI to be installed and user to be logged in

set -e

# Function to display usage
usage() {
    echo "Usage: $0 -n <namespace> -a <argocd-namespace> [-s] [-p <project-name>]"
    echo "  -n    Namespace where uipathadmin service account exists"
    echo "  -a    ArgoCD namespace"
    echo "  -s    Use shared ArgoCD instance (optional)"
    echo "  -p    Project name for shared instance (required if -s is specified)"
    echo "  -h    Display this help message"
    exit 1
}

# Parse command line arguments
while getopts "n:a:sp:h" opt; do
    case ${opt} in
        n )
            NAMESPACE=$OPTARG
            ;;
        a )
            ARGOCD_NAMESPACE=$OPTARG
            ;;
        s )
            SHARED_INSTANCE=true
            ;;
        p )
            PROJECT_NAME=$OPTARG
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
if [ -z "$NAMESPACE" ] || [ -z "$ARGOCD_NAMESPACE" ]; then
    echo "Error: Both namespace (-n) and argocd-namespace (-a) are required"
    usage
fi

if [ "$SHARED_INSTANCE" = true ] && [ -z "$PROJECT_NAME" ]; then
    echo "Error: Project name (-p) is required when using shared instance (-s)"
    usage
fi

echo "Configuring ArgoCD permissions:"
echo "Namespace: $NAMESPACE"
echo "ArgoCD Namespace: $ARGOCD_NAMESPACE"
echo "Shared Instance: ${SHARED_INSTANCE:-false}"
if [ "$SHARED_INSTANCE" = true ]; then
    echo "Project Name: $PROJECT_NAME"
fi

# Create temporary directory for YAML files
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Create role for limit range management
cat > "$TMPDIR/limit-range-role.yaml" << EOF
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: limit-range-manager
  namespace: $NAMESPACE
rules:
  - apiGroups: ["*"]
    resources: ["limitranges"]
    verbs: ["get", "watch", "list", "patch", "update", "create"]
EOF

# Create role for application management
cat > "$TMPDIR/app-manager-role.yaml" << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: uipath-application-manager
  namespace: $ARGOCD_NAMESPACE
rules:
- apiGroups:
  - argoproj.io
  resources:
  - applications
  verbs:
  - "*"
EOF

# Create role for secret management
cat > "$TMPDIR/secret-role.yaml" << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argo-secret-role
  namespace: $ARGOCD_NAMESPACE
rules:
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["*"]
  - apiGroups: ["*"]
    resources: ["secrets"]
    verbs: ["get", "watch", "list", "patch", "update", "create"]
EOF

# Apply the roles
echo "Creating roles..."
oc apply -f "$TMPDIR/limit-range-role.yaml"
oc apply -f "$TMPDIR/app-manager-role.yaml"
oc apply -f "$TMPDIR/secret-role.yaml"

# Create role bindings
echo "Creating role bindings..."

# Limit range manager binding
if [ "$SHARED_INSTANCE" = true ]; then
    oc -n $NAMESPACE create rolebinding limit-range-manager-binding \
      --role=limit-range-manager \
      --serviceaccount=$ARGOCD_NAMESPACE:openshift-gitops-argocd-application-controller
else
    oc -n $NAMESPACE create rolebinding limit-range-manager-binding \
      --role=limit-range-manager \
      --serviceaccount=$ARGOCD_NAMESPACE:argocd-argocd-application-controller
fi

# Application manager binding
oc -n $ARGOCD_NAMESPACE create rolebinding uipath-application-manager \
  --role=uipath-application-manager --serviceaccount=$NAMESPACE:uipathadmin

# Secret management binding
oc -n $ARGOCD_NAMESPACE create rolebinding secret-binding \
  --role=argo-secret-role --serviceaccount=$NAMESPACE:uipathadmin

echo "Successfully configured ArgoCD permissions"
