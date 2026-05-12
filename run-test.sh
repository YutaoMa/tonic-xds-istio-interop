#!/usr/bin/env bash
#
# Runs the tonic-xds channel example inside the Kind cluster against
# Istio's xDS control plane (istiod).
#
# Prerequisites: ./setup.sh has been run successfully.
#
# What this does:
# 1. Ensures the tonic-xds-client deployment is applied and running
# 2. Restarts it to pick up any image changes
# 3. Streams its logs (Ctrl-C to stop)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_NAME="xds-test"
NAMESPACE="xds-test"

info()  { printf "\033[1;34m==> %s\033[0m\n" "$*"; }
error() { printf "\033[1;31mERROR: %s\033[0m\n" "$*" >&2; exit 1; }

# ── Verify cluster is reachable ────────────────────────────────────
kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 \
    || error "Cluster 'kind-${CLUSTER_NAME}' not reachable. Run ./setup.sh first."

# ── Deploy / restart tonic-xds-client ───────────────────────────────────
info "Applying tonic-xds-client deployment..."
kubectl apply -f "$SCRIPT_DIR/k8s/tonic-xds-client.yaml"

info "Restarting tonic-xds-client to pick up latest image..."
kubectl -n "$NAMESPACE" rollout restart deployment/tonic-xds-client
kubectl -n "$NAMESPACE" rollout status deployment/tonic-xds-client --timeout=60s

# ── Stream logs ───────────────────────────────────────────────────
info "Streaming tonic-xds-client logs (Ctrl-C to stop)..."
echo ""
kubectl -n "$NAMESPACE" logs -f deployment/tonic-xds-client
