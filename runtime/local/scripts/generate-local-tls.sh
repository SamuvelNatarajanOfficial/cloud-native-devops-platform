#!/usr/bin/env bash
# Generates a self-signed TLS certificate for LOCAL runtime validation
# only (Phase 7), then creates a Kubernetes TLS Secret from it directly -
# the private key is never written anywhere this repo tracks, and never
# passed through a committed YAML file.
#
# This has NOTHING to do with ACM (terraform/modules/dns) - see
# docs/local-runtime-validation.md#local-tls for the explicit distinction.
# A self-signed cert proves the Ingress -> TLS termination -> Service
# mechanism works; it proves nothing about ACM certificate issuance/
# validation/renewal, which requires a real AWS environment.
set -euo pipefail

CONTEXT="${KUBE_CONTEXT:-docker-desktop}"
NAMESPACE="taskflow"
HOST="taskflow.local"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tls/generated"

mkdir -p "$OUT_DIR"

echo "Generating self-signed certificate for ${HOST} (kept out of Git - see .gitignore)..."
# -subj carries only O= (no CN=): modern TLS clients (curl included)
# verify against subjectAltName, not the deprecated CN field, so the SAN
# entry below is what actually matters. This also sidesteps a Git-Bash-
# for-Windows quirk where a leading "/" in -subj's value gets rewritten
# as if it were a filesystem path.
openssl req -x509 -nodes -days 30 \
  -newkey rsa:2048 \
  -keyout "${OUT_DIR}/tls.key" \
  -out "${OUT_DIR}/tls.crt" \
  -subj "//O=taskflow-local" \
  -addext "subjectAltName=DNS:${HOST}"

echo "Creating/updating the taskflow-local-tls Secret in the ${NAMESPACE} namespace (context: ${CONTEXT})..."
kubectl --context "${CONTEXT}" -n "${NAMESPACE}" create secret tls taskflow-local-tls \
  --cert="${OUT_DIR}/tls.crt" \
  --key="${OUT_DIR}/tls.key" \
  --dry-run=client -o yaml | kubectl --context "${CONTEXT}" apply -f -

echo "Done. The generated cert/key remain only in ${OUT_DIR} (gitignored) and in the cluster's own Secret."
