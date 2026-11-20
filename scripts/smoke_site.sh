#!/usr/bin/env bash
# Fetch the Worker at URL and require HTTP 200 with the site title in the body.
# Used on the workers.dev address, not the custom domain (Bot Fight Mode on the
# zone can answer a GitHub runner with 403).
set -Eeuo pipefail

url="${1:-}"
if [ -z "$url" ]; then
  echo "usage: smoke_site.sh <url>" >&2
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
