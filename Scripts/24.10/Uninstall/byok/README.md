# Automation Suite Uninstall Script (BYOK)

Removes UiPath Automation Suite from a bring-your-own-Kubernetes (AKS/EKS/
generic Kubernetes) or OpenShift cluster. It is the script equivalent of
`uipathctl manifest delete`, and it is the same script that runs in the
Automation Suite install pipelines' **UninstallAS** stage, so every release
exercises it against real AKS, EKS and OpenShift clusters.

Although it lives under `24.10/`, the script is **version-agnostic**: it works
for 24.10, 25.10, 26.10 and later, because it *discovers* what to remove
instead of hardcoding a per-version component list. It uses the same markers
`uipathctl` sets during installation:

- ArgoCD Applications carrying `spec.info[] {name: InstalledBy, value: UiPath}`
- Helm releases carrying the `installedBy=UiPath` marker (in the release values
  or as a label on the Helm release secret)

Anything without those markers — your own ArgoCD, cert-manager, Istio, or any
release you installed yourself — is never touched.

## Prerequisites

- `kubectl` (Kubernetes) or `oc` (OpenShift), configured against the target
  cluster (`KUBECONFIG`)
- `helm`
- `jq`

Your user needs permission to delete the resources listed under
[Teardown order](#teardown-order) in the target namespaces (cluster-admin, or
the same permissions used to install).

## Usage

```bash
./uninstall.sh [DISTRIBUTION] [OPTIONS]
```

### Distribution

- `k8s` — standard Kubernetes, uses `kubectl` (default)
- `openshift` — uses `oc`, also checks the `openshift-gitops` namespace for
  Applications, and handles SCCs. OLM operators (openshift-gitops,
  cert-manager) are cluster prerequisites installed by the cluster
  administrator, not by uipathctl — the script never removes them

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Display help message and exit |
| `-d, --dry-run` | Show what would be deleted without deleting anything |
| `-v, --verbose` | Show detailed information during execution |
| `-y, --yes` | Skip the confirmation prompt (for automation) |
| `--excluded COMP1,COMP2` | Components to keep (comma-separated) |
| `--clusterconfig FILE` | JSON file with an `exclude_components` array |
| `--istioNamespace NS` | Custom Istio namespace (default: `istio-system`) |
| `--uipathNamespace NS` | Custom UiPath namespace (default: `uipath`) |
| `--argocdNamespace NS` | Custom ArgoCD namespace (default: `argocd`) |
| `--timeout SECONDS` | Wait per deletion before escalating (default: 300) |
| `--delete-unmarked-namespaces` | Also delete namespaces without the `uipath.com/created-by=uipathctl` label (for full test-cluster teardowns and installs made by uipathctl versions that predate the marker) |

### Components (for `--excluded`)

`uipath`, `authentication` (Kubernetes only), `falco`, `gatekeeper`,
`cert_manager`, `shared_gitops` (OpenShift only), `argocd`, `istio`

Excluding a component keeps its Helm releases, RBAC leftovers and namespace.
Excluding `uipath` also keeps all ArgoCD Applications.

## Examples

```bash
# Always preview first
./uninstall.sh k8s --dry-run --verbose

# Full uninstall on Kubernetes
./uninstall.sh k8s

# Full uninstall on OpenShift, non-interactive
./uninstall.sh openshift --yes --verbose

# Keep shared cluster infrastructure you also use for other workloads
./uninstall.sh k8s --excluded istio,argocd

# Non-default namespaces
./uninstall.sh k8s --uipathNamespace automation-suite --argocdNamespace gitops

# Read the exclusions from your cluster config
./uninstall.sh k8s --clusterconfig cluster_config.json
```

`cluster_config.json` only needs the exclusion array:

```json
{
  "exclude_components": ["istio", "cert_manager"]
}
```

## Teardown order

1. **ArgoCD Applications first**, while ArgoCD is still running, so the
   application controller cascade-deletes the deployed resources. Applications
   stuck on `resources-finalizer.argocd.argoproj.io` are escalated by removing
   their finalizers after `--timeout` seconds.
2. **Marked Helm releases** afterwards, in reverse dependency order: UiPath
   products first, then cert-manager, argocd, and Istio last (within Istio:
   istio-configure → gateway → istiod → base).
3. **Leftover CRD instances and admission webhooks** are cleaned up so nothing
   can block namespace teardown, then **namespaces are deleted**; namespaces
   stuck in `Terminating` are force-finalized.
4. **Roles and rolebindings go last** — in-cluster controllers (dapr operator,
   argocd) still need their RBAC to process finalizers while the namespaces
   terminate. The final pass sweeps cluster-scoped leftovers and RBAC in
   surviving namespaces.

## Safety

Only what uipathctl installed is deleted; resources you created are left in
place:

- **Bring-your-own protection**: Helm releases and ArgoCD Applications without
  the `installedBy=UiPath` marker are never deleted.
- **Leftover cleanup is gated per component**: RBAC, CRD instances, webhooks
  and namespaces of a component are only cleaned up when a UiPath-installed
  release or application was actually discovered for it. A bring-your-own
  Istio or cert-manager never has its custom resources or namespace touched.
- **Namespace marker**: only namespaces labeled
  `uipath.com/created-by=uipathctl` are deleted, so namespaces you pre-created
  survive. Use `--delete-unmarked-namespaces` to override.
- Refuses to delete `default`, `kube-*` and `openshift-*` namespaces under any
  configuration.
- `y/N` confirmation prompt before deleting (skip with `--yes`).
- `--dry-run` is supported end to end.

## Error handling

**Missing resources never abort the run.** Every deletion is best-effort:

- Anything not discovered (no marker) is simply not touched. Running the
  script against an already-uninstalled cluster is a no-op — each phase logs
  "none found" and moves on.
- Existence is probed before acting (`kubectl get`, `helm status`); absent
  CRDs, namespaces, applications and releases are skipped with a verbose log,
  and all deletes pass `--ignore-not-found`.
- Only a **failed deletion of something that exists** produces a `WARNING` and
  makes the script exit non-zero at the very end, after everything else was
  still attempted.

## Troubleshooting

- Re-run with `--verbose` to see every probe and deletion.
- Permission errors mean your user lacks rights on the resource named in the
  warning; re-run with cluster-admin.
- If a namespace is still `Terminating` after the run, a resource in it has a
  finalizer owned by a controller that was already deleted. Re-running the
  script force-finalizes it.
- The script is idempotent — re-running it after a partial failure is safe.
