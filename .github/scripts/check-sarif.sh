#!/usr/bin/env bash
# Fail closed on CodeQL output: every scanned language must have a non-empty,
# well-formed SARIF file, and none of them may hold a result.
#
# Usage: check-sarif.sh <sarif dir> <comma-separated languages>
# Exits 0 only when each <lang>.sarif exists, is non-empty, has at least one run,
# gives every run a results array, and holds zero results in total.
set -Eeuo pipefail

if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "::error::usage: check-sarif.sh <sarif dir> <comma-separated languages>"
  exit 2
fi
dir=$1
IFS=',' read -r -a languages <<<"$2"

total=0
for lang in "${languages[@]}"; do
  lang=${lang//[[:space:]]/}
  if [ -z "$lang" ]; then
    echo "::error::empty language name in '$2'"
    exit 1
  fi
  file="${dir}/${lang}.sarif"
  if [ ! -f "$file" ]; then
    echo "::error::no SARIF file for ${lang} at ${file}"
    exit 1
  fi
  if [ ! -s "$file" ]; then
    echo "::error::${file} is empty"
    exit 1
  fi
  if ! jq -e '(.runs | type == "array" and length > 0)
      and all(.runs[]; has("results") and (.results | type == "array"))' \
      "$file" >/dev/null 2>&1; then
    echo "::error::${file} has no runs, or a run without a results array"
    exit 1
  fi
  count=$(jq '[.runs[].results[]] | length' "$file")
  jq -r '.runs[].results[] |
    "::error file=\(.locations[0].physicalLocation.artifactLocation.uri // ""),line=\(.locations[0].physicalLocation.region.startLine // 1),title=\(.ruleId // "codeql")::\(.message.text // "CodeQL result")"' \
    "$file"
  echo "${lang}.sarif: ${count} result(s)"
  total=$((total + count))
done

if [ "$total" -ne 0 ]; then
  echo "::error::CodeQL reported ${total} result(s)"
  exit 1
fi
echo "CodeQL: no results"
