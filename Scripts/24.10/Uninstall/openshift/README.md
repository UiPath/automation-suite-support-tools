# UiPath Kubernetes Component Manager

A comprehensive utility script for managing UiPath Automation Suite components on Kubernetes and OpenShift environments.

## Overview

This tool helps administrators manage UiPath Automation Suite deployments by providing the ability to selectively keep or remove components. It's particularly useful for:

- Cleaning up failed or unwanted installations
- Performing selective upgrades
- Troubleshooting component-specific issues
- Managing multi-environment deployments

## Features

- **Kubernetes and OpenShift Support**: Includes separate scripts optimized for each platform
- **Component-Based Architecture**: Granular control over which components to keep or remove
- **Dry Run Mode**: Preview changes before making them
- **Verbose Output**: Detailed information during execution
- **Safe Execution**: Proper ordering of resource deletion to prevent dependency issues

## Available Components

### Kubernetes Version
- **istio**: Service mesh for ingress and networking
- **argocd**: GitOps deployment tool
- **uipath**: Core UiPath applications
- **cert_manager**: Certificate management (required for Process Mining)
- **dapr**: Distributed Application Runtime (required for Process Mining)
- **authentication**: Keycloak components
- **cluster_permissions**: Cluster-level roles and permissions
- **priority_classes**: Priority classes for scheduling

### OpenShift Version
All of the above, plus:
- **shared_gitops**: Shared OpenShift GitOps configuration
- **redis**: Redis Enterprise deployed via OperatorHub
- **airflow**: Airflow components for Process Mining

## Prerequisites

### Kubernetes Version
- `kubectl` command-line tool installed and configured
- `helm` command-line tool installed
- Appropriate permissions to manage the UiPath resources

### OpenShift Version
- `oc` (OpenShift CLI) command-line tool installed and configured
- `helm` command-line tool installed
- Appropriate permissions to manage the UiPath resources

## Installation

1. Download the appropriate script for your environment:
    - `uipath-os-uninstall.sh` for Kubernetes (AKS/EKS)
    - `uipath-os-uninstall` for OpenShift

2. Make the script executable:
   ```bash
   chmod +x uipath-os-uninstall.sh
   # OR
   chmod +x uipath-os-uninstall
   ```

## Usage

### Basic Command Format

```bash
./uipath-os-uninstall.sh [OPTIONS] [COMPONENT_NAMES]
```

### Options

- `-h, --help`: Display help message and exit
- `-d, --dry-run`: Perform a dry run (no actual deletion)
- `-v, --verbose`: Show detailed information during execution

### Examples

Keep specific components and delete all others:
```bash
# Keep istio and argocd components, delete everything else
./uipath-os-uninstall.sh istio argocd

# OpenShift version
./uipath-os-uninstall istio shared_gitops
```

Preview what would be deleted without making any changes:
```bash
./uipath-os-uninstall.sh --dry-run
```

Show detailed information during execution:
```bash
./uipath-os-uninstall.sh --verbose
```

See all available components and help:
```bash
./uipath-os-uninstall.sh --help
```

## Adding New Components

To add a new component to the script:

1. Edit the `define_components` function
2. Add a new component definition following the format:
   ```bash
   new_component="
       helm:chart-name
       helm:another-chart:custom-namespace
       role:component-role
       role:admin-role:custom-namespace
       rolebinding:component-binding
       argocd:component-app
       namespace:custom-namespace
   "
   ```
3. Add the component name to the list returned by `get_all_components`

## Resource Types

The script can manage the following resource types:

- Helm charts
- Roles and ClusterRoles
- RoleBindings and ClusterRoleBindings
- ArgoCD applications
- Namespaces/Projects
- Priority Classes
- Operators (OpenShift)
- Security Context Constraints (OpenShift)

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure you have the necessary permissions to delete resources
   ```
   Error: forbidden: User ... cannot delete resource
   ```
   Solution: Use a user or service account with appropriate permissions

2. **Resource Not Found**: The script will ignore these errors by default
   ```
   Error: helmchart "component" not found
   ```

3. **Dependency Errors**: Resources cannot be deleted due to dependencies
   Solution: The script attempts to delete resources in the correct order, but you may need to manually delete certain resources

4. **OpenShift vs Kubernetes Commands**: Using the wrong script for your platform
   Solution: Use `uipath-os-uninstall` for OpenShift and `uipath-os-uninstall.sh` for Kubernetes

## License

Copyright © 2025 UiPath. All rights reserved.