# OpenShift Service Installation Scripts

A collection of installation scripts for setting up core services on OpenShift clusters.

## Prerequisites

- OpenShift CLI (`oc`) or Kubernetes CLI (`kubectl`)
- Access to an OpenShift cluster with administrator privileges
- `jq` (required for Redis installation)
- Bash shell environment

## Scripts Overview

### 1. ArgoCD (`argocd.sh`)
Installs and configures ArgoCD for GitOps deployments.

Features:
- Supports dedicated or shared instance types
- Cluster-wide or namespace-scoped modes
- Helm repository configuration
- Automatic operator and instance deployment

Usage:
```bash
# Interactive mode
./argocd.sh -i

# CLI mode
./argocd.sh \
  --instance-type dedicated \
  --namespace argocd \
  --uipath-ns uipath \
  --cluster-wide true \
  --repo-url your-repo-url \
  --repo-user username \
  --repo-pass password \
  --repo-name repo-name
```

### 2. Cert Manager (`cert-manager.sh`)
Installs OpenShift Cert Manager for certificate management.

Features:
- Automated operator deployment
- Configurable resource paths
- Status verification for deployments

Usage:
```bash
./cert-manager.sh
```

### 3. Service Mesh/Istio (`istio.sh`)
Installs Red Hat OpenShift Service Mesh (Istio).

Features:
- Configurable TLS protocol versions
- Integrated Kiali, Jaeger, and Prometheus
- Memory-based Jaeger storage
- Automatic operator deployment

Usage:
```bash
./istio.sh
```

### 4. Priority Class (`priorityclass.sh`)
Configures namespace priority classes and labels.

Features:
- Creates high-priority class
- Sets up namespace labels for Istio injection
- Enables UiPath injection

Usage:
```bash
./priorityclass.sh -n your-namespace
```

### 5. Redis (`redis.sh`)
Installs Redis Enterprise on OpenShift.

Features:
- Security Context Constraints setup
- Redis Enterprise Cluster deployment
- Database creation and configuration
- Optional operator installation

Usage:
```bash
./redis.sh
```

## Common Features Across Scripts

- Automated prerequisite checking
- Resource validation
- Progress monitoring
- Error handling
- Temporary file cleanup
- Configurable timeout parameters
- Namespace management

## Installation Order

Recommended installation order:

1. Cert Manager (`cert-manager.sh`)
2. Service Mesh (`istio.sh`)
3. Redis (`redis.sh`)
4. ArgoCD (`argocd.sh`)
5. Priority Class (`priorityclass.sh`)
