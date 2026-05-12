# tonic-xds Istio interop harness

A reviewer-runnable, Kind-based test harness for validating
[tonic-xds](https://github.com/hyperium/tonic/tree/master/tonic-xds) against
[Istio](https://istio.io)'s xDS control plane (istiod). Designed to be reused
across xDS feature PRs — pin the `TONIC_REF` to the PR under test, run
`./setup.sh && ./run-test.sh`, observe.

## What it spins up

- A local **Kind** cluster (`xds-test`).
- **Istio** (demo profile) installed via `istioctl`.
- A `greeter` Deployment (the tonic-xds `greeter_server` example) — two
  replicas, sidecar-injected.
- An `tonic-xds-client` Deployment (the tonic-xds `channel` example) — talks to
  istiod for xDS and to the greeter replicas over the resolved endpoints.

## Prerequisites

- Docker (running)
- `kubectl`
- The scripts install `kind` and `istioctl` automatically if missing
  (via Homebrew on macOS, or direct download).

## Usage

```bash
./setup.sh        # provision cluster, install Istio, build & deploy
./run-test.sh     # apply tonic-xds-client, tail its logs
./teardown.sh     # delete the Kind cluster
```

`setup.sh` clones tonic into `./tonic-src/` (gitignored) and reuses it on
subsequent runs. The PR / branch under test is hardcoded near the top of
`setup.sh` — edit `TONIC_REPO_URL` and `TONIC_REF` to switch:

```bash
TONIC_REPO_URL="https://github.com/hyperium/tonic.git"
TONIC_REF="refs/pull/2640/head"
```

To force a fresh clone, `rm -rf ./tonic-src/`.

## Current scenario

The default configuration exercises the **plaintext** xDS path: tonic-xds-client
connects to istiod on port `15010` over plaintext, receives Listener / RDS /
CDS / EDS resources, and connects to greeter pods over plaintext gRPC.

A29 mTLS scenario (proxyless mTLS via SPIFFE identities) is on the
roadmap — see `TODO: scenarios/a29-mtls/` once added.

## Layout

```
.
├── Dockerfile          # Multi-stage build for greeter_server + channel
├── k8s/
│   ├── namespace.yaml  # xds-test namespace with sidecar injection
│   ├── greeter.yaml    # Greeter Deployment + Service
│   └── tonic-xds-client.yaml # tonic-xds channel client + bootstrap inline
├── setup.sh            # Provision Kind + Istio, build & deploy greeter
├── run-test.sh         # Deploy tonic-xds-client, stream its logs
└── teardown.sh         # Delete the Kind cluster
```
