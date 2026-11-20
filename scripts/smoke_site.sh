#!/usr/bin/env bash
# Require the homepage and Kubernetes guide on the deployed Worker.
# Used on the workers.dev address, not the custom domain (Bot Fight Mode on the
# zone can answer a GitHub runner with 403). A second argument, when set, is
# the release tag that site/version.txt must serve.
set -Eeuo pipefail

url="${1:-}"
expected="${2:-}"
if [ -z "$url" ]; then
  echo "usage: smoke_site.sh <url> [expected_version]" >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# wrangler reports an origin; request the homepage.
code="$(curl --silent --show-error --location --max-time 20 \
  --output "$tmp" --write-out '%{http_code}' "${url}/" || true)"

echo "GET ${url}/ answered HTTP ${code:-none}"
if [ "$code" != 200 ]; then
  echo "::error::${url} did not return HTTP 200" >&2
  exit 1
fi
if ! grep -q 'Security Toolbox' "$tmp"; then
  echo "::error::${url} did not serve the Security Toolbox site" >&2
  exit 1
fi

guide_code="$(curl --silent --show-error --location --max-time 20 \
  --output "$tmp" --write-out '%{http_code}' "${url}/kubernetes/" || true)"
echo "GET ${url}/kubernetes/ answered HTTP ${guide_code:-none}"
if [ "$guide_code" != 200 ] || ! grep -Fq 'Cluster (GKE)' "$tmp"; then
  echo "::error::${url}/kubernetes/ did not serve the Kubernetes guide" >&2
  exit 1
fi

if [ -n "$expected" ]; then
  vcode="$(curl --silent --show-error --location --max-time 20 \
    --output "$tmp" --write-out '%{http_code}' "${url}/version.txt" || true)"
  echo "GET ${url}/version.txt answered HTTP ${vcode:-none}"
  if [ "$vcode" != 200 ]; then
    echo "::error::${url}/version.txt did not return HTTP 200" >&2
    exit 1
  fi
  got="$(tr -d '\r\n' < "$tmp")"
  if [ "$got" != "$expected" ]; then
    echo "::error::${url}/version.txt served '${got}', not '${expected}'" >&2
    exit 1
  fi
fi
