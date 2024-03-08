#!/bin/bash

# =================
# legal_placeholder
# =================

# Global Variables:
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || { echo "Could not determine script path" ; exit 1; }
MODULES_DIR=$(cd "${SCRIPT_DIR}/../../Modules" && pwd) || { echo "Could not determine modules path" ; exit 1; }

source "${MODULES_DIR}/utils.sh"

# Patch function to patch finalizer:
patch_resource() {
    RESOURCE="$1"
    NAME="$2"
    NAMESPACE="$3"
    CMD="kubectl --request-timeout=30s patch $RESOURCE $NAME -p '{\"metadata\":{\"finalizers\":null}}' --type=merge "
    if [[ -n "$NAMESPACE" ]]; then
        CMD="kubectl --request-timeout=30s patch $RESOURCE $NAME -n $NAMESPACE -p '{\"metadata\":{\"finalizers\":null}}' --type=merge "
    fi
    if kubectl get "$RESOURCE" "$NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.finalizers}' | grep -q "wrangler.cattle.io"; then
        info "Patching finalizer for $RESOURCE $NAME ${NAMESPACE:+in namespace $NAMESPACE}"
        until eval "$CMD"; do sleep 15; done
    fi
}


# Define the resources to check:
RESOURCES_CLUSTER_SCOPED=("clusterrolebindings" "clusterroles")
RESOURCES_NAMESPACE_SCOPED=("rolebindings" "roles")

# Iterate through cluster scoped resources:
for RESOURCE in "${RESOURCES_CLUSTER_SCOPED[@]}"; do
    info "Fetching cluster scoped $RESOURCE..."
    NAMES=$(kubectl get "$RESOURCE" -o jsonpath='{.items[*].metadata.name}')
    for NAME in $NAMES; do  # Check each resource for the finalizer
        patch_resource "$RESOURCE" "$NAME"
    done
done

# Iterate through namespaces:
for NAMESPACE in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
    info "Checking namespace $NAMESPACE..."
    for RESOURCE in "${RESOURCES_NAMESPACE_SCOPED[@]}"; do
        info "Fetching namespace scoped $RESOURCE in namespace $NAMESPACE..."
        RESOURCE_NAMES=$(kubectl get "$RESOURCE" -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
        for NAME in $RESOURCE_NAMES; do
            patch_resource "$RESOURCE" "$NAME" "$NAMESPACE"
        done
    done
done

info "Patching finalizers for wrangler.cattle.io finished"