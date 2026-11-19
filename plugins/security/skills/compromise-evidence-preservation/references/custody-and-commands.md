# Custody sheet and capture checklist

Read this when opening a case and again before each capture. It holds the sheet template, the per-platform checklist and the questions that decide contain-now or observe-first.

## Contents

- Contain or observe
- Chain-of-custody sheet
- Capture checklist by platform
- Closing check

## Contain or observe

Write the answer and the reason. Choose contain-now when any of these holds: data is leaving, destructive actions are under way, the actor has a path to other systems, or credentials with wide reach are on the host. Observe-first is defensible only when responders can see the actor's activity in real time, the observation has a time limit, the legal owner has agreed, and the host holds nothing that cannot be recovered. If unsure, isolate on the network (step 2 in the skill): it stops most new connections and keeps memory, but established connections can survive a rule change, so verify the traffic stopped before relying on it.

## Chain-of-custody sheet

One row per artefact per hand-off. Times in UTC.

| Field | Entry |
| --- | --- |
| Case ID | |
| Artefact ID | memory-01, vol-root-snap-01 |
| Description | what it is and which system |
| Captured by | name |
| Captured at (UTC) | ISO 8601 |
| Responder clock offset | against a trusted source, with the command used |
| Source location | host, volume, account, region |
| Method and tool version | for example the acquisition tool and its version |
| SHA-256 at capture | |
| Transferred from, to | |
| SHA-256 after transfer | must equal the capture hash |
| Stored at | bucket or project, with the retention mode |
| Next custodian | name and time |

Rules: no row is edited after it is written, corrections are new rows; the sheet itself is stored in the locked bucket.

## Capture checklist by platform

Linux instance: memory image, network connections, process list, logged-in users, loaded modules, mounted filesystems, scheduled jobs list, then volume snapshots, then shell history and authentication logs copied off-host.

AWS account: trail logs from the trail bucket (event history alone covers only 90 days of management events), `validate-logs` result, IAM credential report (`aws iam generate-credential-report`, then `aws iam get-credential-report`), policies attached to affected identities, security group and network ACL rules, flow logs, S3 server access logs and data events, DNS query logs, GuardDuty findings export.

GCP project: audit logs from `_Required` (400 days) and `_Default` (30 days unless raised), whether Data Access logs were enabled, IAM policies and service-account keys of affected identities, firewall rules and effective firewall policies, VPC flow logs and firewall rules logging.

Kubernetes: node memory, pod specs (`kubectl get pod POD -o yaml`), NetworkPolicies and CNI policies in effect before containment, events, `kubectl logs --previous`, the audit log if enabled, image digests in use, and the container filesystem diff before the pod is replaced.

SaaS and identity provider: export sign-in and admin audit logs through the vendor's export or API, since on-screen history rolls quickly; note the export time and the account used.

## Closing check

- Every artefact has a capture hash and a transfer hash that match.
- The log bucket is in compliance mode (or the GCS retention policy or log bucket is locked) and the retention end date is recorded.
- Containment was verified with a test connection and flow logs, and the results are in the sheet.
- No original volume was mounted writable.
- The list of things not captured, with reasons, is attached.
