#!/usr/bin/env bash
# Run each check against its fixtures: good input must exit 0, bad input must exit 1.
set -Eeuo pipefail
cd "$(dirname "$0")"

fail=0
expect() { # expect <exit code> <description> <command...>
  local want=$1 what=$2 got=0; shift 2
  "$@" >/tmp/check-test.out 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then
    echo "ok   - $what (exit $got)"
  else
    echo "FAIL - $what (wanted exit $want, got $got)"; cat /tmp/check-test.out; fail=1
  fi
}

expect 0 "gke good cluster" gke/gke-report.sh --file gke/fixtures/cluster-good.json
expect 1 "gke bad cluster" gke/gke-report.sh --file gke/fixtures/cluster-bad.json
expect 0 "kubernetes good workloads" kubernetes/cis-workload-report.sh \
  --pods kubernetes/fixtures/pods-good.json --bindings kubernetes/fixtures/bindings-good.json
expect 1 "kubernetes bad workloads" kubernetes/cis-workload-report.sh \
  --pods kubernetes/fixtures/pods-bad.json --bindings kubernetes/fixtures/bindings-bad.json
expect 0 "gcp good iam policy" gcp/iam-report.sh --file gcp/fixtures/policy-good.json --domain example.com
expect 1 "gcp bad iam policy" gcp/iam-report.sh --file gcp/fixtures/policy-bad.json --domain example.com

# The bad fixtures must trip every control they were written for.
expect 0 "gke bad trips 9 failures" bash -c \
  'gke/gke-report.sh --file gke/fixtures/cluster-bad.json | grep -qx "failures: 9"'
expect 0 "kubernetes bad trips 14 findings" bash -c \
  'kubernetes/cis-workload-report.sh --pods kubernetes/fixtures/pods-bad.json --bindings kubernetes/fixtures/bindings-bad.json | grep -qx "findings: 14"'
expect 0 "gcp bad trips 3 failures" bash -c \
  'gcp/iam-report.sh --file gcp/fixtures/policy-bad.json --domain example.com | grep -qx "failures: 3"'
expect 0 "gcp bad reports an outside domain" bash -c \
  'gcp/iam-report.sh --file gcp/fixtures/policy-bad.json --domain example.com | grep -q "from another domain"'
# Ephemeral containers and workload wrappers (Deployment, CronJob) are walked too.
# shellcheck disable=SC2016 # $1 expands inside the bash -c script
for want in 'privileged containers +default/debug +container debugger' \
  'privileged containers +apps/deployment/web +container app' \
  'host namespaces +apps/cronjob/backup +hostIPC'; do
  expect 0 "kubernetes bad reports: $want" bash -c \
    'kubernetes/cis-workload-report.sh --pods kubernetes/fixtures/pods-bad.json --bindings kubernetes/fixtures/bindings-bad.json | grep -Eq "$1"' _ "$want"
done

exit "$fail"
