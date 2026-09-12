#!/usr/bin/env bash
# Phase 7 local runtime bootstrap. Builds the TaskFlow images, deploys
# ingress-nginx + TaskFlow + the observability stack onto whatever local
# Kubernetes cluster the current kubectl context points at, and prints
# the commands you'd use to actually access everything afterward.
#
# This project's own Phase 7 validation used Docker Desktop's built-in
# Kubernetes (the "docker-desktop" context) - NOT Kind, despite this
# directory's "runtime/local" naming being cluster-agnostic. See
# docs/local-runtime-validation.md for exactly why, and what would differ
# on Kind (extraPortMappings for ingress instead of Docker Desktop's
# built-in LoadBalancer->localhost mapping being the main one).
#
# Safe/idempotent: every step uses `helm upgrade --install` or
# `kubectl apply`, and this script never deletes anything outside the
# namespaces it creates. It does NOT install ArgoCD (see
# docs/local-runtime-validation.md#argocd-gitops-runtime-validation for
# why that's a separate, manual, one-time step this script deliberately
# doesn't automate) and does NOT touch any namespace it didn't create.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

CONTEXT="${KUBE_CONTEXT:-docker-desktop}"
KCTL="kubectl --context ${CONTEXT}"
HCTL="helm --kube-context ${CONTEXT}"

echo "==> Using kubectl context: ${CONTEXT}"
${KCTL} cluster-info > /dev/null || {
  echo "ERROR: cannot reach the '${CONTEXT}' context. Enable Kubernetes in"
  echo "Docker Desktop (Settings -> Kubernetes -> Enable Kubernetes), or"
  echo "set KUBE_CONTEXT to point at a different local cluster (e.g. a"
  echo "kind cluster's own context)."
  exit 1
}

echo "==> Building application images (local tag, never pushed anywhere)"
docker build -t taskflow/api-gateway:local ./services/api-gateway
docker build -t taskflow/task-service:local ./services/task-service

echo "==> Installing ingress-nginx (n ingress-nginx)"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx > /dev/null
helm repo update ingress-nginx > /dev/null
${HCTL} upgrade --install ingress-nginx ingress-nginx/ingress-nginx --version 4.15.1 \
  -n ingress-nginx --create-namespace \
  -f runtime/local/ingress/ingress-nginx-values-local.yaml
${KCTL} -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=120s

echo "==> Deploying TaskFlow (n taskflow)"
${HCTL} upgrade --install taskflow helm/taskflow \
  -n taskflow --create-namespace \
  -f helm/taskflow/values-dev.yaml \
  -f runtime/local/values/taskflow-values-local.yaml
${KCTL} -n taskflow rollout status deployment/taskflow-api-gateway --timeout=120s
${KCTL} -n taskflow rollout status deployment/taskflow-task-service --timeout=120s
${KCTL} -n taskflow rollout status statefulset/taskflow-postgres --timeout=120s

echo "==> Generating local self-signed TLS cert + applying local Ingress"
KUBE_CONTEXT="${CONTEXT}" bash runtime/local/scripts/generate-local-tls.sh
${KCTL} apply -f runtime/local/manifests/ingress-local.yaml

echo "==> Deploying observability stack (n monitoring)"
${KCTL} create namespace monitoring --dry-run=client -o yaml | ${KCTL} apply -f -
${KCTL} -n monitoring get secret grafana-admin-credentials > /dev/null 2>&1 || \
  ${KCTL} -n monitoring create secret generic grafana-admin-credentials \
    --from-literal=admin-user=admin \
    --from-literal=admin-password='local-dev-only-not-a-real-secret'

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts > /dev/null
helm repo add grafana https://grafana.github.io/helm-charts > /dev/null
helm repo update prometheus-community grafana > /dev/null

${HCTL} upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 90.0.0 -n monitoring \
  -f observability/prometheus/values-dev.yaml \
  -f runtime/local/values/prometheus-values-local.yaml

${HCTL} upgrade --install loki grafana/loki --version 7.3.0 -n monitoring \
  -f observability/loki/values-dev.yaml \
  -f runtime/local/values/loki-values-local.yaml

${HCTL} upgrade --install alloy grafana/alloy --version 1.12.1 -n monitoring \
  -f observability/alloy/values-dev.yaml \
  -f runtime/local/values/alloy-values-local.yaml

${KCTL} apply -f observability/manifests/

echo
echo "==> Done. Useful commands:"
echo
echo "  # Application (self-signed cert - curl needs -k):"
echo "  curl -sk --resolve taskflow.local:443:127.0.0.1 https://taskflow.local/health"
echo "  curl -sk --resolve taskflow.local:443:127.0.0.1 https://taskflow.local/api/tasks"
echo
echo "  # Grafana (admin / local-dev-only-not-a-real-secret):"
echo "  ${KCTL} -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80"
echo
echo "  # Prometheus:"
echo "  ${KCTL} -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
echo
echo "  # Alertmanager:"
echo "  ${KCTL} -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093"
echo
echo "  # Loki (query API directly):"
echo "  ${KCTL} -n monitoring port-forward svc/loki-gateway 3100:80"
echo
echo "See docs/local-runtime-validation.md for the full validation this"
echo "environment was actually put through, and runtime/local/scripts/down.sh"
echo "to tear it down again."
