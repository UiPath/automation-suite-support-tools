# Automation Suite Uninstall Script

This document explains how to use the `uninstall.sh` script to remove UiPath Automation Suite components from Kubernetes or OpenShift clusters.

## Overview

The uninstall script is designed to help you cleanly remove Automation Suite components from your cluster. It can target specific components while preserving others based on your needs.

## Prerequisites

- For Kubernetes: `kubectl` installed and configured
- For OpenShift: `oc` installed and configured
- `helm` installed
- `jq` installed (optional, used for parsing JSON configuration)

## Usage

```bash
./uninstall.sh [DISTRIBUTION] [OPTIONS]
```

### Distribution Options

- `k8s` - Use standard Kubernetes resources and commands (default)
- `openshift` - Use OpenShift resources and commands

### Command Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Display help message and exit |
| `-d, --dry-run` | Perform a dry run (no actual deletion) |
| `-v, --verbose` | Show detailed information during execution |
| `--excluded COMPONENT1,COMPONENT2` | Components to exclude from deletion (comma-separated) |
| `--clusterconfig FILE` | Path to cluster configuration JSON file with excluded_components array |
| `--istioNamespace NAMESPACE` | Custom namespace for Istio components (default: istio-system) |
| `--uipathNamespace NAMESPACE` | Custom namespace for UiPath components (default: uipath) |
| `--argocdNamespace NAMESPACE` | Custom namespace for ArgoCD components (default: argocd) |

## Available Components

The script can manage the following components:

- `istio` - Istio service mesh components
- `istio_configure` - Istio configuration components
- `argocd` - ArgoCD GitOps components
- `uipath` - UiPath Automation Suite components
- `cert_manager` - Certificate manager
- `network_policies` - Network policies
- `gatekeeper` - Gatekeeper policy engine
- `falco` - Falco security monitoring
- `shared_gitops` - OpenShift GitOps shared components (OpenShift only)

## Example Usage

### Basic Usage

Remove all components from a Kubernetes cluster:

```bash
./uninstall.sh k8s
```

Remove all components from an OpenShift cluster:

```bash
./uninstall.sh openshift
```

### Exclude Specific Components

Keep Istio and ArgoCD components while removing all others:

```bash
./uninstall.sh k8s --excluded istio,argocd
```

### Dry Run

Preview what would be deleted without making any changes:

```bash
./uninstall.sh k8s --dry-run
```

### Using a Configuration File

You can specify excluded components in a JSON configuration file:

```bash
./uninstall.sh k8s --clusterconfig cluster_config.json
```

Example `cluster_config.json` format:
```json
{
  "exclude_components": ["istio", "cert_manager"]
}
```

### Custom Namespaces

If your components are installed in non-default namespaces:

```bash
./uninstall.sh k8s --uipathNamespace custom-uipath --istioNamespace custom-istio
```

#### Examples for Custom Namespace Configuration

1. Change only UiPath components namespace:

```bash
./uninstall.sh k8s --uipathNamespace automation-suite
```

2. Change all component namespaces:

```bash
./uninstall.sh k8s --uipathNamespace automation-suite --istioNamespace service-mesh --argocdNamespace gitops
```

3. Use custom namespaces with component exclusion:

```bash
./uninstall.sh openshift --uipathNamespace prod-automation --excluded istio,argocd
```

4. Custom namespaces with dry run to verify correct targeting:

```bash
./uninstall.sh k8s --uipathNamespace custom-uipath --istioNamespace custom-istio --dry-run --verbose
```

## Resource Types Managed

The script handles the deletion of various resource types:

- Helm charts
- Namespaces
- Roles and ClusterRoles
- RoleBindings and ClusterRoleBindings
- ArgoCD Applications
- OpenShift Operators (OpenShift only)
- PriorityClasses
- SecurityContextConstraints (OpenShift only)
- Custom Resource Definitions (CRDs)

## Safety Features

- The script checks prerequisites before proceeding
- Use `--dry-run` to preview changes without making them
- Components are processed in a logical order to minimize issues
- The script skips resources that don't exist instead of throwing errors

## Troubleshooting

- If you encounter permission errors, ensure your Kubernetes/OpenShift user has sufficient privileges
- Use the `--verbose` flag to see detailed information about each operation
- Check that the namespaces match where your components are actually installed

## Notes for OpenShift Users

When using the script with OpenShift:
- The script uses `oc` instead of `kubectl`
- It handles OpenShift-specific resources like Projects, SCCs, and Operators
- Some components like `shared_gitops` are specific to OpenShift environments
