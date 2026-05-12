# tonic-xds Istio interop harness

A reviewer-runnable, Kind-based test harness for validating
[tonic-xds](https://github.com/hyperium/tonic/tree/master/tonic-xds) against
[Istio](https://istio.io)'s xDS control plane (istiod). Designed to be reused
across xDS feature PRs — pin the tonic-xds git rev in `Cargo.toml`, run
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

The tonic-xds revision under test is pinned in `Cargo.toml` as a git
dependency. Edit the `rev` (or switch to `branch = "..."`) to point at a
different PR or branch:

```toml
tonic-xds = { git = "https://github.com/hyperium/tonic.git", rev = "66d77c5a", features = [...] }
```

Cargo fetches into its own cache; no separate clone step is needed.

## Current scenario: A29 mTLS (proxyless gRPC against Istio)

Exercises gRFC A29 end-to-end. The `tonic-xds-client` pod is injected with
Istio's `grpc-agent` template, which:

- Runs `pilot-agent` in cert-agent-only mode (no iptables, no L7 proxy).
- Mounts SPIFFE workload credentials at
  `/var/run/secrets/workload-spiffe-credentials/`:
  `cert.pem`, `key.pem`, `ca.crt`. Issued and rotated by Istio's CA.

`PeerAuthentication: STRICT` on the `xds-test` namespace makes the greeter
sidecar reject plaintext (forces inbound mTLS). For istiod to *emit*
`transport_socket: UpstreamTlsContext` in the CDS for the greeter cluster
(outbound side, required for proxyless gRPC clients to know they should TLS),
an explicit `DestinationRule` with `tls.mode: ISTIO_MUTUAL` is also needed —
`PeerAuthentication` alone is not enough on the outbound emit path. Both
manifests are applied by `setup.sh`. The resulting `UpstreamTlsContext`
references the bootstrap `default` provider and carries a SAN matcher for
the greeter's SPIFFE identity (`spiffe://cluster.local/ns/xds-test/sa/greeter`).

The tonic-xds bootstrap (inline in `k8s/tonic-xds-client.yaml`) configures
a `file_watcher` certificate provider named `default` pointing at the
Istio-mounted SPIFFE paths. `XdsServerCertVerifier` reads CA roots through
that provider; `TlsConnector` reads identity through it too. The result is
mTLS handshake against the greeter's sidecar, signed by Istio's CA, with
A29 SAN matching applied.

### Verifying it worked

`./run-test.sh` tails the tonic-xds-client logs. Look for:

- xDS bootstrap parsed, `certificate_providers` entry resolved.
- CDS update received with `transport_socket` for the `greeter` cluster.
- TLS handshake completes (no `CertificateError` or `ApplicationVerificationFailure`).
- gRPC unary calls return successful `HelloReply`s from the two greeter
  replicas, distributed by the P2C balancer.

## Layout

```
.
├── Dockerfile          # Multi-stage build for greeter_server + channel
├── k8s/
│   ├── namespace.yaml           # xds-test namespace with sidecar injection
│   ├── peer-authentication.yaml # PeerAuthentication: STRICT (inbound mTLS)
│   ├── destination-rule.yaml    # ISTIO_MUTUAL (triggers UpstreamTlsContext in CDS)
│   ├── greeter.yaml             # Greeter Deployment + Service
│   └── tonic-xds-client.yaml    # tonic-xds channel client + inline bootstrap
├── setup.sh            # Provision Kind + Istio, build & deploy greeter
├── run-test.sh         # Deploy tonic-xds-client, stream its logs
└── teardown.sh         # Delete the Kind cluster
```
