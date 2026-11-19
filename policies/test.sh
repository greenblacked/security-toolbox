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

# Fixtures are JSON/YAML and would otherwise be loaded as OPA data documents.
expect pass "opa fmt --list --fail" opa fmt --list --fail opa
expect pass "opa check --strict" opa check --strict --ignore fixtures opa
expect pass "opa test" opa test -v --ignore fixtures opa

expect pass "terraform plan good" conftest test -p opa/terraform -n terraform.gcp opa/terraform/fixtures/plan-good.json
expect fail "terraform plan bad" conftest test -p opa/terraform -n terraform.gcp opa/terraform/fixtures/plan-bad.json
# Exact counts so a policy that silently stops matching is caught.
count_conftest() { # count_conftest <policy dir> <namespace> <file> <failures> <warnings>
  conftest test --no-fail -p "$1" -n "$2" -o json "$3" | python3 -c '
import json, sys
d = json.load(sys.stdin)[0]
f, w = len(d.get("failures") or []), len(d.get("warnings") or [])
print(f"failures={f} warnings={w}")
sys.exit(0 if (f, w) == (int(sys.argv[1]), int(sys.argv[2])) else 1)' "$4" "$5"
}
expect pass "terraform plan bad: 18 failures, 1 warning" count_conftest opa/terraform terraform.gcp opa/terraform/fixtures/plan-bad.json 18 1
expect pass "kubernetes bad: 8 failures, 2 warnings" count_conftest opa/kubernetes kubernetes.pod_security opa/kubernetes/fixtures/pod-bad.yaml 8 2
expect pass "kubernetes good" conftest test -p opa/kubernetes -n kubernetes.pod_security opa/kubernetes/fixtures/deployment-good.yaml
expect fail "kubernetes bad" conftest test -p opa/kubernetes -n kubernetes.pod_security opa/kubernetes/fixtures/pod-bad.yaml

if command -v checkov >/dev/null 2>&1; then
  ids=CKV_STB_GCP_1,CKV_STB_GCP_2,CKV_STB_GCP_3,CKV_STB_GCP_4
  expect pass "checkov good" checkov -d checkov/fixtures/good --external-checks-dir checkov/checks --check "$ids" --quiet --compact
  expect fail "checkov bad" checkov -d checkov/fixtures/bad --external-checks-dir checkov/checks --check "$ids" --quiet --compact
  # The bad fixture must fail all four checks on every resource (12), and the
  # good fixture must pass on every resource (6).
  count_checkov() { # count_checkov <dir> <passed> <failed>
    checkov -d "$1" --external-checks-dir checkov/checks --check "$ids" --compact -o json --soft-fail \
      | python3 -c '
import json, sys
r = json.load(sys.stdin)["results"]
p, f = len(r["passed_checks"]), len(r["failed_checks"])
ids = {c["check_id"] for c in r["failed_checks"]}
print(f"passed={p} failed={f} failing_ids={sorted(ids)}")
want_p, want_f = int(sys.argv[1]), int(sys.argv[2])
sys.exit(0 if (p, f) == (want_p, want_f) and (want_f == 0 or len(ids) == 4) else 1)' "$2" "$3"
  }
  expect pass "checkov good: 6 passed, 0 failed" count_checkov checkov/fixtures/good 6 0
  expect pass "checkov bad: 0 passed, 12 failed across all four checks" count_checkov checkov/fixtures/bad 0 12
else
  echo "skip - checkov not installed"
fi

exit "$fail"
