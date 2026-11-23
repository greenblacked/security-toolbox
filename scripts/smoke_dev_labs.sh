#!/usr/bin/env bash
# Verify the lab routes and exact archive bytes for the preview deployment.
set -Eeuo pipefail

url=${1:-}
url=${url%/}
expected=${2:-}
if [[ "$url" != https://* || ! "$expected" =~ ^[a-f0-9]{64}$ ]]; then
  echo "usage: smoke_dev_labs.sh <https-url> <build-sha256>" >&2
  exit 2
fi

body=$(mktemp)
trap 'rm -f -- "$body"' EXIT

fetch() {
  curl --silent --show-error --proto '=https' --max-time 20 --output "$body" \
    --write-out "$2" "$url$1"
}

check_html() {
  local path=$1 marker=$2 response
  # No redirect following: a header from another URL cannot satisfy this check.
  response=$(fetch "$path" '%{http_code} %{content_type} %header{x-content-type-options}')
  if [[ "$response" != "200 text/html"*' nosniff' ]] || ! grep -Fq -- "$marker" "$body"; then
    echo "::error::$path did not serve the expected HTML and security header ($response)" >&2
    return 1
  fi
}

redirect=$(fetch /labs '%{http_code} %header{location}')
case "$redirect" in
  "301 /labs/"|"302 /labs/"|"307 /labs/"|"308 /labs/") ;;
  *) echo "::error::Unexpected /labs redirect ($redirect)" >&2; exit 1 ;;
esac

check_html /labs/ 'Hands-on security labs'
check_html /labs/tls-rotation/ 'Verify TLS certificate rotation'

path=/labs/security-toolbox-labs.tar.gz
response=$(fetch "$path" '%{http_code} %{content_type} %header{x-content-type-options}')
if [ "$response" != '200 application/gzip nosniff' ]; then
  echo "::error::$path did not serve a gzip archive with nosniff ($response)" >&2
  exit 1
fi
if ! printf '%s  %s\n' "$expected" "$body" | sha256sum --check --status; then
  echo "::error::$path differs from the archive built for this preview deployment" >&2
  exit 1
fi
python3 "$(dirname "$0")/check_lab_archive.py" "$body"
echo "Preview lab routes and archive SHA-256 verified"
