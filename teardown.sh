#!/usr/bin/env bash
# Tears down the local Kind cluster used for Istio xDS testing.
set -euo pipefail

CLUSTER_NAME="xds-test"

printf "\033[1;34m==> Deleting Kind cluster '%s'...\033[0m\n" "$CLUSTER_NAME"
kind delete cluster --name "$CLUSTER_NAME"
printf "\033[1;34m==> Done.\033[0m\n"
