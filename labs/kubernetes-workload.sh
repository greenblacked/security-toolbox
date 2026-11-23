#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 || ! -f "$1" || ! -r "$1" || ! -f "$2" || ! -r "$2" ]]; then
  echo "Usage: $0 PODS_JSON BINDINGS_JSON (two readable fixture files required)" >&2
  exit 2
fi

kit_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
lab_home=$(mktemp -d)
trap 'rm -rf -- "$lab_home"' EXIT
env -i PATH="$PATH" HOME="$lab_home" KUBECONFIG="$lab_home/config" \
  bash "$kit_root/checks/kubernetes/cis-workload-report.sh" --pods "$1" --bindings "$2"
