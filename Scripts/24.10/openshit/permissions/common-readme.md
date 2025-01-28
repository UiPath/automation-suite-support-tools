# UiPath Automation Suite Permission Setup Scripts

## Overview

This collection of scripts automates the setup of required permissions and configurations for UiPath Automation Suite deployment on OpenShift. The scripts handle service account creation, Istio configuration, ArgoCD setup, and product-specific permissions.

## Scripts Included

1. **create-uipathadmin.sh**
    - Creates service account and kubeconfig
    - Sets up basic admin permissions
    - Generates authentication tokens
    - Supports debug mode for troubleshooting

2. **istio-permissions.sh**
    - Configures Istio system permissions
    - Sets up WASM plugin permissions (optional)
    - Creates necessary roles and bindings
    - Includes debug mode for detailed execution tracking

3. **argocd-permissions.sh**
    - Configures ArgoCD permissions
    - Supports both dedicated and shared instances
    - Sets up application and secret management
    - Features debug output for troubleshooting

4. **product-permissions.sh**
    - Sets up Process Mining and Dapr permissions
    - Supports both dedicated and shared ArgoCD instances
    - Note: Process Mining installation automatically includes Dapr configuration
    - Includes debug mode for detailed execution logs

## Prerequisites

- OpenShift cluster with admin access
- OpenShift CLI (`oc`) installed and configured
- Bash shell environment
- Active cluster login
- Required infrastructure:
    - Istio service mesh installed
    - ArgoCD/OpenShift GitOps configured
    - Access to required namespaces

## Quick Start

1. **Clone and Set Up**
```bash
git clone <repository-url>
cd uipath-permission-scripts
chmod +x *.sh
```

2. **Create Service Account**
```bash
./create-uipathadmin.sh -n uipath [-d]
```

3. **Configure Istio**
```bash
./istio-permissions.sh -n uipath -i istio-system [-w] [-d]
```

4. **Set Up ArgoCD**
```bash
# For dedicated instance
./argocd-permissions.sh -n uipath -a argocd [-d]

# For shared instance
./argocd-permissions.sh -n uipath -a openshift-gitops -s -p myproject [-d]
```

5. **Configure Product Permissions**
```bash
./product-permissions.sh -n uipath -a argocd -p pm [-d]
```

## Common Parameters

| Parameter | Description | Used In |
|-----------|-------------|----------|
| -n | Target namespace | All scripts |
| -i | Istio namespace | istio-permissions.sh |
| -a | ArgoCD namespace | argocd-permissions.sh, product-permissions.sh |
| -s | Use shared ArgoCD | argocd-permissions.sh |
| -w | Enable WASM plugin | istio-permissions.sh |
| -p | Products/Project | product-permissions.sh, argocd-permissions.sh |
| -d | Enable debug mode | All scripts |
| -h | Help message | All scripts |

## Debug Mode

All scripts support a debug mode that can be enabled with the `-d` flag. When enabled, debug mode:
- Shows detailed execution information
- Displays commands as they are executed
- Prints variable expansions and substitutions
- Helps identify where failures occur
- Provides verbose output for troubleshooting

Example usage with debug mode:
```bash
./script-name.sh [other-options] -d
```

## Common Use Cases

1. **Basic Installation**
```bash
# Step 1: Service Account
./create-uipathadmin.sh -n uipath [-d]

# Step 2: Istio Setup
./istio-permissions.sh -n uipath -i istio-system [-d]

# Step 3: ArgoCD Configuration
./argocd-permissions.sh -n uipath -a argocd [-d]

# Step 4: Process Mining Setup
# Process Mining setup (includes Dapr)
./product-permissions.sh -n uipath -a argocd -p pm [-d]
```

2. **Full Installation with WASM**
```bash
./create-uipathadmin.sh -n uipath [-d]
./istio-permissions.sh -n uipath -i istio-system -w [-d]
./argocd-permissions.sh -n uipath -a argocd [-d]
./product-permissions.sh -n uipath -a argocd -p pm,dapr [-d]
```

3. **Shared ArgoCD Setup**
```bash
./create-uipathadmin.sh -n uipath [-d]
./istio-permissions.sh -n uipath -i istio-system [-d]
./argocd-permissions.sh -n uipath -a openshift-gitops -s -p myproject [-d]
./product-permissions.sh -n uipath -a openshift-gitops -p pm [-d]
```

## Verification Steps

After running the scripts, verify the setup:

1. **Service Account**
```bash
oc get serviceaccount uipathadmin -n <namespace>
oc get rolebinding -n <namespace>
```

2. **Istio Configuration**
```bash
oc get role -n <istio-namespace>
oc get rolebinding -n <istio-namespace>
```

3. **ArgoCD Setup**
```bash
oc get role -n <argocd-namespace>
oc get rolebinding -n <argocd-namespace>
```

4. **Product Permissions**
```bash
# For Process Mining
oc get role -n <namespace> | grep cert-manager
# Verify Dapr label
oc get namespace <namespace> --show-labels
```

### Troubleshooting

1. **Enable Debug Mode**
```bash
# Run the failing script with debug mode
./script-name.sh [options] -d
```

2. **Check Logs**
```bash
oc logs <pod-name> -n <namespace>
```

3. **Verify Permissions**
```bash
oc auth can-i <verb> <resource> -n <namespace>
```

4. **Reset Configuration**
```bash
# Remove and recreate resources
oc delete role <role-name> -n <namespace>
oc delete rolebinding <binding-name> -n <namespace>
```

## Additional Resources

- [UiPath Openshift Permissions](https://docs.uipath.com/automation-suite/automation-suite/2024.10/installation-guide-openshift/granting-installation-permissions)