#!/usr/bin/env bash
#
# Sets up a local Kind cluster with Istio for testing tonic-xds against
# a real xDS control plane (istiod).
#
# Usage:
#   ./setup.sh                 # full setup
#   ./setup.sh --skip-build    # skip Docker image build (reuse existing)
#
# The tonic-xds revision under test is pinned in `Cargo.toml`. Edit the `rev`
# (or switch to `branch = "..."`) there to point at a different PR.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_NAME="xds-test"
ISTIO_VERSION="1.24.2"

info()  { printf "\033[1;34m==> %s\033[0m\n" "$*"; }
warn()  { printf "\033[1;33mWARN: %s\033[0m\n" "$*"; }
error() { printf "\033[1;31mERROR: %s\033[0m\n" "$*" >&2; exit 1; }

# ── Pre-flight checks ──────────────────────────────────────────────
command -v docker >/dev/null || error "docker is required"

# ── Install kind if missing ─────────────────────────────────────────
if ! command -v kind >/dev/null; then
    info "Installing kind..."
    if command -v brew >/dev/null; then
        brew install kind
    else
        # Direct binary download
        KIND_ARCH="$(uname -m)"
        [[ "$KIND_ARCH" == "x86_64" ]] && KIND_ARCH="amd64"
        [[ "$KIND_ARCH" == "arm64" || "$KIND_ARCH" == "aarch64" ]] && KIND_ARCH="arm64"
        curl -Lo /usr/local/bin/kind \
            "https://kind.sigs.k8s.io/dl/v0.25.0/kind-$(uname -s | tr '[:upper:]' '[:lower:]')-${KIND_ARCH}"
        chmod +x /usr/local/bin/kind
    fi
fi

# ── Install istioctl if missing ─────────────────────────────────────
if ! command -v istioctl >/dev/null; then
    info "Installing istioctl ${ISTIO_VERSION}..."
    if command -v brew >/dev/null; then
        brew install istioctl
    else
        curl -L https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIO_VERSION" sh -
        export PATH="$PWD/istio-${ISTIO_VERSION}/bin:$PATH"
        warn "istioctl installed to ./istio-${ISTIO_VERSION}/bin — add it to your PATH"
    fi
fi

# ── Create Kind cluster ────────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    info "Kind cluster '${CLUSTER_NAME}' already exists, reusing"
else
    info "Creating Kind cluster '${CLUSTER_NAME}'..."
    kind create cluster --name "$CLUSTER_NAME" --wait 60s
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null \
    || error "Cannot reach cluster"

# ── Install Istio ──────────────────────────────────────────────────
info "Installing Istio (demo profile)..."
istioctl install --set profile=demo -y \
    --set meshConfig.defaultConfig.proxyMetadata.ISTIO_META_DNS_CAPTURE=true

# Wait for istiod
info "Waiting for istiod to be ready..."
kubectl -n istio-system wait deployment/istiod \
    --for=condition=available --timeout=120s

# ── Build & load image ─────────────────────────────────────────────
if [[ "${1:-}" != "--skip-build" ]]; then
    info "Building tonic-xds-client + greeter image (this may take a while)..."
    docker build \
        -t greeter-server:latest \
        -f "$SCRIPT_DIR/Dockerfile" \
        "$SCRIPT_DIR"

    info "Loading image into Kind cluster..."
    kind load docker-image greeter-server:latest --name "$CLUSTER_NAME"
else
    info "Skipping Docker build (--skip-build)"
fi

# ── Deploy greeter service ─────────────────────────────────────────
info "Deploying greeter service..."
kubectl apply -f "$SCRIPT_DIR/k8s/namespace.yaml"
kubectl apply -f "$SCRIPT_DIR/k8s/peer-authentication.yaml"
kubectl apply -f "$SCRIPT_DIR/k8s/destination-rule.yaml"
kubectl apply -f "$SCRIPT_DIR/k8s/greeter.yaml"

info "Waiting for greeter pods to be ready..."
kubectl -n xds-test wait deployment/greeter \
    --for=condition=available --timeout=120s

# ── Summary ────────────────────────────────────────────────────────
echo ""
info "Setup complete!"
echo ""
echo "  Cluster:  kind-${CLUSTER_NAME}"
echo "  istiod:   running in istio-system namespace"
echo "  Greeter:  2 replicas in xds-test namespace"
echo ""
echo "Greeter pods:"
kubectl -n xds-test get pods -l app=greeter -o wide
echo ""
echo "Next step: run the test with ./run-test.sh"
