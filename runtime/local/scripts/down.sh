#!/usr/bin/env bash
# Tears down everything runtime/local/scripts/up.sh (or the manual Phase 7
# validation steps in docs/local-runtime-validation.md) created - and
# ONLY that. This script:
#   - never touches any namespace it didn't create (kube-system,
#     kube-public, kube-node-lease, default, or any OTHER namespace
#     already on your cluster before running up.sh, are left completely
#     alone)
#   - never deletes Docker images, volumes, or containers unrelated to
#     this project
#   - never touches AWS resources (there are none to touch - nothing in
#     this directory ever creates any)
#   - does NOT disable Kubernetes in Docker Desktop itself - that's a
#     manual Settings toggle, left for you to do (or not) separately
#
# ArgoCD (if you installed it manually, following
# docs/local-runtime-validation.md#argocd-gitops-runtime-validation) is
# NOT removed by this script either - it's a manual, one-time install
# this project's own scripts never automate. Remove it yourself with:
#   kubectl --context <ctx> delete namespace argocd
set -euo pipefail

CONTEXT="${KUBE_CONTEXT:-docker-desktop}"
KCTL="kubectl --context ${CONTEXT}"
HCTL="helm --kube-context ${CONTEXT}"

echo "==> Using kubectl context: ${CONTEXT}"
echo "==> This will delete ONLY the following namespaces: taskflow, monitoring, ingress-nginx"
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

for release_ns in "taskflow taskflow" "kube-prometheus-stack monitoring" "loki monitoring" "alloy monitoring" "ingress-nginx ingress-nginx"; do
  set -- $release_ns
  release="$1"; ns="$2"
  ${HCTL} uninstall "$release" -n "$ns" 2>/dev/null || echo "  (release $release not found in $ns - skipping)"
done

# metrics-server was installed into kube-system (Step 23) - remove only
# that one release, never anything else in kube-system.
${HCTL} uninstall metrics-server -n kube-system 2>/dev/null || echo "  (metrics-server release not found - skipping)"

${KCTL} delete namespace taskflow monitoring ingress-nginx --ignore-not-found --timeout=60s

echo "==> Done. kube-system, default, and any other pre-existing namespace were left untouched."
echo "==> Docker images (taskflow/api-gateway:local, taskflow/task-service:local) were NOT removed - remove manually with 'docker rmi' if desired."
