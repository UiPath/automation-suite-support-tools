#!/bin/bash

# Script to apply miscellaneous configurations for UiPath Automation Suite
# This script requires 'oc' CLI to be installed and user to be logged in

set -e

# Function to display usage
usage() {
    echo "Usage: $0 -n <namespace>"
    echo "  -n    Namespace to configure"
    echo "  -h    Display this help message"
    exit 1
}

# Parse command line arguments
while getopts "n:h" opt; do
    case ${opt} in
        n )
            NAMESPACE=$OPTARG
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
if [ -z "$NAMESPACE" ]; then
    echo "Error: Namespace (-n) is required"
    usage
fi

# Create temporary directory for YAML files
TMPDIR=$(mktemp -d)
echo "Temp Directory: $TMPDIR"

# Create priority class YAML
cat > "$TMPDIR/priority-class.yaml" << EOF
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: $NAMESPACE-high-priority
value: 1000000
preemptionPolicy: PreemptLowerPriority
globalDefault: false
description: "Priority class for uipath applications"
EOF

# Apply configurations
echo "Applying configurations for namespace: $NAMESPACE"

echo "Creating priority class..."
oc apply -f "$TMPDIR/priority-class.yaml"

echo "Labeling namespace..."
oc label namespace $NAMESPACE uipath-injection=enabled
oc label namespace $NAMESPACE istio-injection=enabled

echo "Configuration completed successfully"