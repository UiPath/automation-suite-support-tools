# UiPath Kubernetes Component Manager

A comprehensive utility script for managing UiPath Automation Suite components in Kubernetes environments.

## Overview

This script helps administrators manage UiPath Automation Suite deployments by providing the ability to selectively keep or remove components. It's particularly useful for:

- Cleaning up failed or unwanted installations
- Performing selective upgrades
- Troubleshooting component-specific issues
- Managing multi-environment deployments

## Features

- **Component-Based Architecture**: Granular control over which components to keep or remove
- **Dry Run Mode**: Preview changes before making them
- **Verbose Output**: Detailed information during execution
- **Safe Execution**: Proper ordering of resource deletion to prevent dependency issues

## Available Components

The script manages the following UiPath components:

- **istio**: Service mesh for ingress and networking
- **argocd**: GitOps deployment tool
- **uipath**: Core UiPath applications and ArgoCD applications including:
    - actioncenter
    - aicenter
    - aievents
    - aimetering
    - airflow
    - aistorage
    - asrobots
    - auth
    - automationhub
    - automationops
    - ba
    - dapr
    - datapipeline-api
    - dataservice
    - documentunderstanding
    - insights
    - integrationservices
    - notificationservice
    - network-policies
    - orchestrator
    - platform
    - processmining
    - pushgateway
    - reloader
    - robotube
    - sfcore
    - studioweb
    - taskmining
    - testmanager
    - webhook
- **cert_manager**: Certificate management (required for Process Mining)
- **dapr**: Distributed Application Runtime (required for Process Mining)
- **authentication**: Keycloak components
- **cluster_permissions**: Cluster-level roles and permissions
- **priority_classes**: Priority classes for scheduling

## Prerequisites

- `kubectl` command-line tool installed and configured
- `helm` command-line tool installed
- Appropriate permissions to manage the UiPath resources

## Installation

1. Download the script:
   ```bash
   wget https://raw.githubusercontent.com/yourorg/repo/main/uipath-uninstall.sh
   ```

2. Make the script executable:
   ```bash
   chmod +x uipath-uninstall.sh
   ```

## Usage

### Basic Command Format

```bash
./uipath-uninstall.sh [OPTIONS] [COMPONENT_NAMES]
```

### Options

- `-h, --help`: Display help message and exit
- `-d, --dry-run`: Perform a dry run (no actual deletion)
- `-v, --verbose`: Show detailed information during execution

### Examples

Keep specific components and delete all others:
```bash
# Keep istio and argocd components, delete everything else
./uipath-uninstall.sh istio argocd
```

Preview what would be deleted without making any changes:
```bash
./uipath-uninstall.sh --dry-run
```

Show detailed information during execution:
```bash
./uipath-uninstall.sh --verbose
```

See all available components and help:
```bash
./uipath-uninstall.sh --help
```

## How It Works

1. The script first identifies which components to keep based on your input
2. It then determines which components to delete
3. For each component to delete:
    - ArgoCD applications are deleted first to prevent reconciliation
    - Helm charts are uninstalled
    - Rolebindings and roles are removed
    - Priority classes are deleted
    - Finally, namespaces are removed

This ordered approach ensures that dependencies are properly handled.

## Resource Types

The script can manage the following resource types:

- Helm charts
- Roles and ClusterRoles
- RoleBindings and ClusterRoleBindings
- ArgoCD applications
- Namespaces
- Priority Classes

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
