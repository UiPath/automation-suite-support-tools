#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
POD_BLUE='\033[0;34m'
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

podName() {
    echo -e "${POD_BLUE}Pod Name: ${GREEN}$1\n${NC}"
}


usage() {
    echo "Usage: $0 <service-account-name> [namespace]"
    echo "  - If namespace is provided, will search only in that namespace"
    echo "  - If namespace is not provided, will search across all namespaces"
    exit 1
}

command -v oc >/dev/null 2>&1 || error "OpenShift CLI (oc) is not installed"

oc whoami >/dev/null 2>&1 || error "Not logged into OpenShift cluster"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
fi

SERVICE_ACCOUNT=$1
NAMESPACE=$2
FOUND_PODS=0

validate_sa() {
    local ns=$1
    local sa=$2

    if ! oc get serviceaccount "$sa" -n "$ns" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

print_sa_details() {
    local ns=$1
    local sa=$2

    echo -e "\nService Account Details:"
    echo "----------------------------------------"
    oc get serviceaccount "$sa" -n "$ns" -o json | jq '{
        "Name": .metadata.name,
        "Namespace": .metadata.namespace,
        "Secrets": [.secrets[].name],
        "Image Pull Secrets": [.imagePullSecrets[].name],
        "Labels": .metadata.labels,
        "Annotations": .metadata.annotations
    }'
}

format_capabilities() {
    local caps=$1
    if [ -z "$caps" ]; then
        echo "None"
    else
        echo "$caps" | jq -r '
            [
                (.add // [] | join(",")),
                (.drop // [] | join(","))
            ] |
            ["ADD:[" + .[0] + "]", "DROP:[" + .[1] + "]"] |
            join(" ")
        '
    fi
}

list_pods() {
    local ns=$1
    local sa=$2

    local pods=$(oc get pods -n "$ns" -o jsonpath="{.items[?(@.spec.serviceAccountName=='$sa')].metadata.name}" 2>/dev/null)
    if [ ! -z "$pods" ]; then
        echo -e "\nPods and Containers:"
        echo "----------------------------------------"

        for pod in $pods; do
            FOUND_PODS=$((FOUND_PODS + 1))
           podName "$pod"
            oc get pod "$pod" -n "$ns" -o json | jq -r --arg pod "$pod" '
                .spec.containers[] |
                {
                    pod_name: $pod,
                    container_name: .name,
                    image: .image,
                    capabilities: (.securityContext.capabilities // null)
                } |
                [.pod_name, .container_name, .image, (.capabilities | @json)]
                | @tsv
            ' | while IFS=$'\t' read -r pod_name container_name image caps; do
                local formatted_caps=$(format_capabilities "$caps")
                echo -e "Container Name: $container_name"
                echo -e "Image: $image"
                echo -e "Capabilities: $formatted_caps"
                echo ""

            done
            echo "-------"
            echo ""

        done
    else
        warn "No pods found using this service account in namespace $ns"
    fi
}


if [ -z "$NAMESPACE" ]; then
    info "Searching for ServiceAccount '$SERVICE_ACCOUNT' across all namespaces..."
    NAMESPACES=$(oc get namespaces -o jsonpath='{.items[*].metadata.name}')
    SA_FOUND=0

    for ns in $NAMESPACES; do
        echo "Searching Namespace ${ns}"
        if validate_sa "$ns" "$SERVICE_ACCOUNT" 2>/dev/null; then
            SA_FOUND=$((SA_FOUND + 1))
            header "Namespace: $ns"
            print_sa_details "$ns" "$SERVICE_ACCOUNT"
            list_pods "$ns" "$SERVICE_ACCOUNT"
        fi
    done

    if [ $SA_FOUND -eq 0 ]; then
        error "ServiceAccount '$SERVICE_ACCOUNT' not found in any namespace"
    fi

    info "ServiceAccount '$SERVICE_ACCOUNT' found in $SA_FOUND namespace(s)"
else
    if ! oc get namespace "$NAMESPACE" >/dev/null 2>&1; then
        error "Namespace '$NAMESPACE' does not exist"
    fi
    if ! validate_sa "$NAMESPACE" "$SERVICE_ACCOUNT"; then
        error "ServiceAccount '$SERVICE_ACCOUNT' not found in namespace '$NAMESPACE'"
    fi
    header "Namespace: $NAMESPACE"
    print_sa_details "$NAMESPACE" "$SERVICE_ACCOUNT"
    list_pods "$NAMESPACE" "$SERVICE_ACCOUNT"
fi

if [ $FOUND_PODS -gt 0 ]; then
    info "Found $FOUND_PODS pod(s) using ServiceAccount '$SERVICE_ACCOUNT'"
fi

