#!/bin/bash

# Script to configure product-specific permissions (Process Mining, Dapr, etc.)
# This script requires 'oc' CLI to be installed and user to be logged in

set -e

# Function to display usage
usage() {
    echo "Usage: $0 -n <namespace> -a <argocd-namespace> [-p product1,product2,...]"
    echo "  -n    Namespace where uipathadmin service account exists"
    echo "  -a    ArgoCD namespace"
    echo "  -p    Comma-separated list of products (pm for Process Mining, dapr for Dapr)"
    echo "  -h    Display this help message"
    exit 1
}

# Parse command line arguments
while getopts "n:a:p:h" opt; do
    case ${opt} in
        n )
            NAMESPACE=$OPTARG
            ;;
        a )
            ARGOCD_NAMESPACE=$OPTARG
            ;;
        p )
            PRODUCTS=$OPTARG
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

# Create temporary directory for YAML files
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Function to configure Process Mining permissions
configure_process_mining() {
    echo "Configuring Process Mining permissions..."
    
    # Create cert-manager role
    cat > "$TMPDIR/cert-manager-role.yaml" << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argocd-cert-manager-role
  namespace: $NAMESPACE
rules:
  - apiGroups: ["cert-manager.io"]
    resources: ["certificates", "issuers"]
    verbs: ["get", "create"]
EOF

    # Create Airflow anyuid role
    cat > "$TMPDIR/anyuid-role.yaml" << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: anyuid-role
  namespace: $NAMESPACE
rules:
  - apiGroups: ["security.openshift.io"]
    resources: ["securitycontextconstraints"]
    resourceNames: ["anyuid"]
    verbs: ["use"]
EOF

    # Apply roles
    echo "Applying Process Mining roles..."
    oc apply -f "$TMPDIR/cert-manager-role.yaml"
    oc apply -f "$TMPDIR/anyuid-role.yaml"

    # Create role bindings
    echo "Creating Process Mining role bindings..."
    if [[ "$ARGOCD_NAMESPACE" == "openshift-gitops" ]]; then
        # For shared ArgoCD instance
        echo "Configuring for shared ArgoCD instance..."
        oc -n $NAMESPACE create rolebinding gitops-cert-manager-binding \
          --role=argocd-cert-manager-role \
          --serviceaccount=$ARGOCD_NAMESPACE:openshift-gitops-argocd-application-controller

        # Note: For shared instance, Airflow anyuid binding is not required
        echo "Note: Airflow anyuid binding not required for shared ArgoCD instance"
    else
        # For dedicated ArgoCD instance
        echo "Configuring for dedicated ArgoCD instance..."
        oc -n $NAMESPACE create rolebinding argocd-cert-manager-binding \
          --role=argocd-cert-manager-role \
          --serviceaccount=$ARGOCD_NAMESPACE:argocd-argocd-application-controller

        # Create Airflow anyuid binding for dedicated instance
        echo "Creating Airflow anyuid binding..."
        oc -n $NAMESPACE create rolebinding argocd-anyuid-binding \
          --role=anyuid-role \
          --serviceaccount=$ARGOCD_NAMESPACE:argocd-argocd-application-controller
    fi
}

# Function to configure Dapr permissions
configure_dapr() {
    echo "Configuring Dapr permissions..."

    # Create cluster role for CRD management
    cat > "$TMPDIR/manage-crds-role.yaml" << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: manage-crds
rules:
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ['*']
  - apiGroups: ["admissionregistration.k8s.io"]
    resources: ["mutatingwebhookconfigurations"]
    verbs: ['*']
EOF

    # Create Dapr creator role
    cat > "$TMPDIR/dapr-creator-role.yaml" << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dapr-creator
  namespace: $NAMESPACE
rules:
  - apiGroups: ["dapr.io"]
    resources: ["components", "configurations", "resiliencies"]
    verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
EOF

    # Apply roles
    echo "Applying Dapr roles..."
    oc apply -f "$TMPDIR/manage-crds-role.yaml"
    oc apply -f "$TMPDIR/dapr-creator-role.yaml"

    # Create role bindings
    echo "Creating Dapr role bindings..."
    if [[ "$ARGOCD_NAMESPACE" == "openshift-gitops" ]]; then
        # For shared ArgoCD instance
        oc create clusterrolebinding manage-crds-binding \
          --clusterrole=manage-crds \
          --serviceaccount=$ARGOCD_NAMESPACE:openshift-gitops-argocd-application-controller

        oc -n $NAMESPACE create rolebinding gitops-dapr-creator-binding \
          --role=dapr-creator \
          --serviceaccount=$ARGOCD_NAMESPACE:openshift-gitops-argocd-application-controller
    else
        # For dedicated ArgoCD instance
        oc create clusterrolebinding manage-crds-binding \
          --clusterrole=manage-crds \
          --serviceaccount=$ARGOCD_NAMESPACE:argocd-argocd-application-controller

        oc -n $NAMESPACE create rolebinding dapr-creator-binding \
          --role=dapr-creator \
          --serviceaccount=$ARGOCD_NAMESPACE:argocd-argocd-application-controller
    fi

    # Label the namespace for Dapr
    echo "Labeling namespace for Dapr..."
    oc label namespace $NAMESPACE uipath-injection=enabled
}

# Main execution
if [ -n "$PRODUCTS" ]; then
    # Convert comma-separated string to array
    IFS=',' read -ra PRODUCT_ARRAY <<< "$PRODUCTS"

    for product in "${PRODUCT_ARRAY[@]}"; do
        case $product in
            "pm")
                echo "Setting up Process Mining permissions (including Airflow)..."
                configure_process_mining
                ;;
            "dapr")
                echo "Setting up Dapr permissions..."
                configure_dapr
                ;;
            *)
                echo "Warning: Unknown product '$product' specified"
                ;;
        esac
    done
else
    echo "No products specified. Use -p option to specify products."
    usage
fi

echo "Successfully configured product-specific permissions"