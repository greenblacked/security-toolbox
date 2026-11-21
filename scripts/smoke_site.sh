#!/usr/bin/env bash
# Verify live URLs on the deployed Worker, using workers.dev to avoid zone-level bot challenges.
set -Eeuo pipefail

url="${1:-}"
expected="${2:-}"
if [ -z "$url" ]; then
  echo "usage: smoke_site.sh <url> [expected_version]" >&2
  exit 1
fi
url="${url%/}"

body="$(mktemp)"
trap 'rm -f "$body"' EXIT

fetch_route() {
  local path="$1" timeout="$2"
  curl --silent --show-error --location --max-time "$timeout" \
    --output "$body" --write-out '%{http_code}' "${url}${path}"
}

wait_for_revision() {
  local status delay
  for delay in 0 2 4 8 16; do
    sleep "$delay"
    status="$(fetch_route /version.txt 5)" || status="unavailable"
    if [ "$status" = 200 ] && [ "$(tr -d '\r\n' < "$body")" = "$expected" ]; then
      echo "GET ${url}/version.txt served the expected revision"
      return 0
    fi
    echo "Waiting for ${url} to serve the expected revision (HTTP $status)"
  done
  echo "::error::${url}/version.txt did not serve the expected revision $expected" >&2
  return 1
}

check_route() {
  local path="$1" marker="$2" status
  status="$(fetch_route "$path" 15)" || status="unavailable"
  echo "GET ${url}${path} answered HTTP $status"
  if [ "$status" != 200 ] || ! grep -Fq -- "$marker" "$body"; then
    echo "::error::${url}${path} did not serve the expected content" >&2
    return 1
  fi
}

if [ -n "$expected" ]; then
  wait_for_revision
fi

check_route / 'id="hero-title"'
check_route /quickstart.js 'quickstart-command'
check_route /home.css '--accent:'
check_route /theme.js 'renderTheme'
check_route /kubernetes/ 'Cluster (GKE)'
check_route /gcp/ 'Organisation policies worth enforcing'
check_route /terraform/ 'Policies in this repository'
check_route /github/ 'Repository baseline'
check_route /secrets/ 'Delivery patterns'
check_route /contributing/ 'Keep checks modular'
check_route /ci/ 'Credentials and GitHub environments'
check_route /checks/ 'Read-only report scripts'
check_route /checks/gke/ 'GKE hardening'
check_route /checks/kubernetes/ 'Kubernetes CIS workload report'
check_route /checks/github-actions/ 'GitHub Actions hardening'
check_route /policies/ 'Public GCS coverage'
check_route /policies/terraform/ 'Terraform GCP policy'
check_route /policies/kubernetes/ 'Kubernetes pod security policy'
check_route /policies/checkov/ 'Checkov GCP checks'
check_route /skills/ 'Security skills'
check_route /skills/iac-review/ 'IaC Review'
check_route /guides.css '.guide-layout'
check_route /search/ 'Search guides'
check_route /search/search_index.json 'Kubernetes / GKE'

if [ "${3:-}" = noindex ]; then
  headers="$(mktemp)"
  trap 'rm -f "$body" "$headers"' EXIT
  curl --fail --silent --show-error --location --max-time 15 --dump-header "$headers" --output /dev/null "$url/"
  if ! grep -iqE '^x-robots-tag:[[:space:]]*noindex' "$headers"; then
    echo "::error::${url}/ is missing X-Robots-Tag: noindex" >&2
    exit 1
  fi
fi
