#!/usr/bin/env bash
# Run every policy against its unit tests and its good/bad fixtures.
# Requires opa and conftest; checkov is optional (skipped with a notice).
# Good fixtures must pass; bad fixtures must fail. Exits non-zero otherwise.
set -Eeuo pipefail
cd "$(dirname "$0")"

fail=0
expect() { # expect <pass|fail> <description> <command...>
  local want=$1 what=$2; shift 2
  if "$@" >/tmp/policy-test.out 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then
    echo "ok   - $what ($got as expected)"
  else
    echo "FAIL - $what (wanted $want, got $got)"; cat /tmp/policy-test.out; fail=1
  fi
}

mapfile -t rego < <(find opa -name '*.rego' | sort)
expect pass "opa fmt" bash -c "test -z \"\$(opa fmt -l ${rego[*]})\""
expect pass "opa check --strict" opa check --strict "${rego[@]}"
expect pass "opa test" opa test "${rego[@]}"

expect pass "terraform plan good" conftest test -p opa/terraform -n terraform.gcp opa/terraform/fixtures/plan-good.json
expect fail "terraform plan bad" conftest test -p opa/terraform -n terraform.gcp opa/terraform/fixtures/plan-bad.json
expect pass "kubernetes good" conftest test -p opa/kubernetes -n kubernetes.pod_security opa/kubernetes/fixtures/deployment-good.yaml
expect fail "kubernetes bad" conftest test -p opa/kubernetes -n kubernetes.pod_security opa/kubernetes/fixtures/pod-bad.yaml

if command -v checkov >/dev/null 2>&1; then
  ids=CKV_STB_GCP_1,CKV2_STB_GCP_2,CKV_STB_GCP_3,CKV_STB_GCP_4
  expect pass "checkov good" checkov -d checkov/fixtures/good --external-checks-dir checkov/checks --check "$ids" --quiet --compact
  expect fail "checkov bad" checkov -d checkov/fixtures/bad --external-checks-dir checkov/checks --check "$ids" --quiet --compact
  # The bad fixture must fail every custom check, not just one.
  expect pass "checkov bad hits all four checks" bash -c \
    "checkov -d checkov/fixtures/bad --external-checks-dir checkov/checks --check $ids --quiet --compact -o json \
     | python3 -c 'import json,sys; d=json.load(sys.stdin); ids={c[\"check_id\"] for c in d[\"results\"][\"failed_checks\"]}; sys.exit(0 if len(ids)==4 else 1)'"
else
  echo "skip - checkov not installed"
fi

exit "$fail"
