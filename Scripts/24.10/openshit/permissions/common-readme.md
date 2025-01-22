# UiPath Automation Suite Permission Setup Scripts

## Overview

This collection of scripts automates the setup of required permissions and configurations for UiPath Automation Suite deployment on OpenShift. The scripts handle service account creation, Istio configuration, ArgoCD setup, and product-specific permissions.

## Scripts Included

1. **create-uipathadmin.sh**
   - Creates service account and kubeconfig
   - Sets up basic admin permissions
   - Generates authentication tokens

2. **istio-permissions.sh**
   - Configures Istio system permissions
   - Sets up WASM plugin permissions (optional)
   - Creates necessary roles and bindings

3. **argocd-permissions.sh**
   - Configures ArgoCD permissions
   - Supports both dedicated and shared instances
   - Sets up application and secret management

4. **product-permissions.sh**
   - Sets up Process Mining permissions
   - Configures Dapr requirements
   - Manages product-specific roles

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
./create-uipathadmin.sh -n uipath
```

3. **Configure Istio**
```bash
./istio-permissions.sh -n uipath -i istio-system [-w]
```

4. **Set Up ArgoCD**
```bash
# For dedicated instance
./argocd-permissions.sh -n uipath -a argocd

# For shared instance
./argocd-permissions.sh -n uipath -a openshift-gitops -s -p myproject
```

5. **Configure Product Permissions**
```bash
./product-permissions.sh -n uipath -a argocd -p pm,dapr
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
| -h | Help message | All scripts |

## Common Use Cases

1. **Basic Installation**
```bash
# Step 1: Service Account
./create-uipathadmin.sh -n uipath

# Step 2: Istio Setup
./istio-permissions.sh -n uipath -i istio-system

# Step 3: ArgoCD Configuration
./argocd-permissions.sh -n uipath -a argocd

# Step 4: Process Mining Setup
./product-permissions.sh -n uipath -a argocd -p pm
```

2. **Full Installation with WASM**
```bash
./create-uipathadmin.sh -n uipath
./istio-permissions.sh -n uipath -i istio-system -w
./argocd-permissions.sh -n uipath -a argocd
./product-permissions.sh -n uipath -a argocd -p pm,dapr
```

3. **Shared ArgoCD Setup**
```bash
./create-uipathadmin.sh -n uipath
./istio-permissions.sh -n uipath -i istio-system
./argocd-permissions.sh -n uipath -a openshift-gitops -s -p myproject
./product-permissions.sh -n uipath -a openshift-gitops -p pm,dapr
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
# For Dapr
oc get role -n <namespace> | grep dapr
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   - Verify cluster admin access
   - Check namespace permissions
   - Validate service account existence

2. **Resource Creation Failures**
   - Check namespace existence
   - Verify role permissions
   - Review existing resources

3. **Integration Issues**
   - Validate Istio installation
   - Check ArgoCD configuration
   - Verify namespace labels

### Resolution Steps

1. **Check Logs**
```bash
oc logs <pod-name> -n <namespace>
```

2. **Verify Permissions**
```bash
oc auth can-i <verb> <resource> -n <namespace>
```

3. **Reset Configuration**
```bash
# Remove and recreate resources
oc delete role <role-name> -n <namespace>
oc delete rolebinding <binding-name> -n <namespace>
```


## License

[License Information]

## Additional Resources

- [UiPath Openshift Permissions](https://docs.uipath.com/automation-suite/automation-suite/2024.10/installation-guide-openshift/granting-installation-permissions)
