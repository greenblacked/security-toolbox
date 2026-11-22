#!/usr/bin/env bash
# Crafted SARIF cases for check-sarif.sh. Every malformed or non-clean input must
# fail; only a clean file per language passes.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
check="${here}/check-sarif.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

clean='{"runs":[{"results":[]}]}'
finding='{"runs":[{"results":[{"ruleId":"actions/demo","message":{"text":"demo"},"locations":[{"physicalLocation":{"artifactLocation":{"uri":"x.yml"},"region":{"startLine":3}}}]}]}]}'

fail=0
# case <name> <want: pass|fail> <languages> then lang=content pairs ("-" = zero-byte)
case_() {
  local name=$1 want=$2 langs=$3 dir got
  shift 3
  dir="${work}/${name}"
  mkdir -p "$dir"
  for pair in "$@"; do
    if [ "${pair#*=}" = "-" ]; then
      : >"${dir}/${pair%%=*}.sarif"
    else
      printf '%s\n' "${pair#*=}" >"${dir}/${pair%%=*}.sarif"
    fi
  done
  if "$check" "$dir" "$langs" >"${work}/out" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then
    echo "ok   - ${name} (${got})"
  else
    echo "FAIL - ${name} (wanted ${want}, got ${got})"
    cat "${work}/out"
    fail=1
  fi
}

case_ clean pass actions "actions=${clean}"
case_ clean-two-languages pass actions,python "actions=${clean}" "python=${clean}"
case_ zero-byte fail actions "actions=-"
case_ no-runs-key fail actions "actions={}"
case_ runs-empty fail actions 'actions={"runs":[]}'
case_ run-missing-results fail actions 'actions={"runs":[{"tool":{}}]}'
case_ one-run-missing-results fail actions 'actions={"runs":[{"results":[]},{"tool":{}}]}'
case_ results-not-array fail actions 'actions={"runs":[{"results":{}}]}'
case_ not-json fail actions "actions=not json"
case_ missing-file fail actions,python "actions=${clean}"
case_ results-present fail actions "actions=${finding}"
case_ results-in-second-language fail actions,python "actions=${clean}" "python=${finding}"
case_ empty-language-list fail "" "actions=${clean}"
case_ clean-three-languages pass actions,python,rust "actions=${clean}" "python=${clean}" "rust=${clean}"
case_ missing-rust fail actions,python,rust "actions=${clean}" "python=${clean}"
case_ results-in-rust fail actions,python,rust "actions=${clean}" "python=${clean}" "rust=${finding}"

exit "$fail"
