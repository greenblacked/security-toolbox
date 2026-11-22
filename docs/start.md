# Start here

**Who this is for:** anyone who has to make a platform safe rather than write about it — engineers new to this repository, and reviewers deciding where to begin.

This site is three things that fit together: **checks** that report what is true now, **policies** that stop the next bad change, and **procedures** for the reviews that need judgement.

Much security documentation is advice only. Advice cannot be enforced, so it goes stale quietly: a sentence recommending Workload Identity reads exactly the same two years later, after the cluster it described has been replaced. Every chapter here links to something you can run, so you can check whether it is still true.

## The three layers

| Layer | The question it answers | What it actually is | Where |
| --- | --- | --- | --- |
| Checks | What is true right now? | Read-only scripts over live state or a saved export, PASS / FAIL / WARN per control | [Checks](/checks/) |
| Policies | What must never ship? | OPA / Conftest rules on plan JSON and rendered manifests, Checkov checks on HCL | [Policies](/policies/) |
| Skills | How do I do this review properly? | Written procedures with gates, expected output and the failure modes | [Skills](/skills/) |

A control that exists only as a sentence in a guide is a suggestion. The same control, as a check you can run and a policy that fails the build, is something you can rely on. That difference is what this repository is built around.

## Pick your starting point

### "Is my environment safe today?"

Run the read-only reports. Nothing below changes anything.

```bash
checks/gcp/iam-report.sh --project prod --domain example.com
checks/gke/gke-report.sh --cluster prod --location europe-west1
checks/kubernetes/cis-workload-report.sh
```

Each exits non-zero on a failure, so the same commands work unchanged in a scheduled job. Read the output as a list of decisions rather than a score: a `FAIL` is a blocker, and a `WARN` is a choice you either fix or record with a reason.

Start with [`gcp/`](/checks/gcp/) — public IAM members and standing basic roles make every other control irrelevant.

### "I need to stop the next bad change"

Put the policies where the change is written, and run them on what will actually be applied.

```bash
# Terraform: the saved plan, not a fresh one
terraform show -json tfplan > plan.json
conftest test --policy policies/opa/terraform --namespace terraform.gcp plan.json

# Kubernetes: rendered manifests, not the Helm chart
kustomize build overlays/prod | conftest test --policy policies/opa/kubernetes \
  --namespace kubernetes.pod_security -

# Terraform source, earlier and faster, on the pull request
checkov -d infra/ --external-checks-dir policies/checkov/checks
```

A policy that only runs at apply time is a report. The gate is the pull request.

### "I have to review something"

The skills are the procedures for work that cannot be reduced to a pass/fail rule:

| If you are | Read |
| --- | --- |
| Reviewing a Terraform plan | [IaC Review](/skills/iac-review/) |
| Reviewing a code change for security | [Security Review](/skills/security-review/) |
| Auditing who can do what | [Access Review](/skills/access-review/) |
| Rotating or containing a credential | [Secret Rotation](/skills/secret-rotation/) |
| Designing a new service or integration | [Threat Model](/skills/threat-model/) |
| Handling a suspected compromise | [Compromise Evidence Preservation](/skills/compromise-evidence-preservation/) |
| Reviewing a container build | [Image Hardening](/skills/image-hardening/) |
| Hiding a host behind a baseline | [Host Hardening](/skills/host-hardening/) |
| Working a dependency alert queue | [Dependency Triage](/skills/dependency-triage/) |
| Writing or tuning a detection | [Detection Engineering](/skills/detection-engineering/) |
| Moving certificates onto automation | [Certificate Automation](/skills/certificate-automation/) |

## Reading order

If you are starting from nothing, read in dependency order rather than alphabetically:

1. **[Google Cloud](/gcp/)** — the organisation, IAM and network that everything else sits on. A permissive project policy defeats every cluster control downstream.
2. **[Kubernetes / GKE](/kubernetes/)** — the workloads, and the cluster controls that bound what a workload can do.
3. **[Terraform](/terraform/)** — how both are created, and how to review the change before it is applied.
4. **[GitHub Actions](/github/)** — how the change reaches production, and what credential it carries.
5. **[Secrets](/secrets/)** — the credential that ties the other four together.

## If you have ten minutes, an hour, or a day

- **Ten minutes:** run one check against your own environment and read the `FAIL` lines. That is the shortest path from reading to knowing.
- **An hour:** add one policy to CI and make it blocking on a new finding. One enforced control beats ten documented ones.
- **A day:** take the review you perform most often, follow its skill end to end on a real change, and write down where the procedure was wrong. That gap is the next thing to fix here.

## What this is not

- **Not a compliance certificate.** A check reads one API surface at one moment. Passing it says the configuration was right when you ran it, not that you are audited.
- **Not a scanner that fixes things.** Everything here reports or fails; nothing remediates. That is deliberate: a change to a production control deserves a reviewed diff.
- **Not exhaustive.** Control-plane and node items that need host access, runtime behaviour after deploy, and anything reachable only through a component outside the repository are named as out of scope where they come up.
- **Not vendor-neutral for its own sake.** It is opinionated toward GCP, GKE, Terraform and GitHub because that is what it is tested against. The reasoning transfers; the exact flags do not.
