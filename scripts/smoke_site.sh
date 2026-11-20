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

check_route() {
  local path="$1" marker="$2" status
  status="$(curl --silent --show-error --location --max-time 15 \
    --output "$body" --write-out '%{http_code}' "${url}${path}")" || status="unavailable"
  echo "GET ${url}${path} answered HTTP $status"
  if [ "$status" != 200 ] || ! grep -Fq -- "$marker" "$body"; then
    echo "::error::${url}${path} did not serve the expected content" >&2
    return 1
  fi
}

check_route / 'Practical security for'
check_route /home.css '--accent:'
check_route /theme.js 'renderTheme'
check_route /kubernetes/ 'Cluster (GKE)'
check_route /gcp/ 'Organisation policies worth enforcing'
check_route /terraform/ 'Policies in this repository'
check_route /github/ 'Repository baseline'
check_route /secrets/ 'Delivery patterns'
check_route /contributing/ 'Keep checks modular'
check_route /ci/ 'Credentials and GitHub environments'
check_route /search/search_index.json 'Kubernetes / GKE'

if [ -n "$expected" ]; then
  check_route /version.txt "$expected"
  deployed="$(tr -d '\r\n' < "$body")"
  if [ "$deployed" != "$expected" ]; then
    echo "::error::${url}/version.txt served '${deployed}', expected '${expected}'" >&2
    exit 1
  fi
fi
