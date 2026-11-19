---
name: compromise-evidence-preservation
description: "Preserve evidence from a suspected compromised host, instance, container or account before containment destroys it: record contain-now versus observe-first, follow order of volatility (memory and live connections, processes, disk, then logs), isolate rather than destroy (quarantine group, standby, cordon, never reboot), capture memory with a purpose-built tool, snapshot to a forensics account, hash every artefact at capture and transfer, lock audit logs in a compliance-mode bucket, and keep a chain-of-custody sheet. Use for \"we think this server is compromised, should I shut it down\", \"snapshot before we terminate\", \"legal wants the logs preserved\", \"how do we keep evidence admissible\". Not for command and mitigation (incident-response), revoking a leaked credential (secret-rotation), analysing the preserved data (intrusion-timeline), the write-up (postmortem)."
allowed-tools: "Read, Grep, Glob"
---

# Compromise Evidence Preservation

Done means another person can reproduce the hash of every artefact, no original was modified, and the decision to contain now or observe first is written down with a name and a time on it.

Containment is the instinct and it is the thing that destroys evidence. Terminating an instance discards its memory and, on most configurations, its root volume. A reboot clears running processes, network connections and anything that lived only in RAM. Logging in as an administrator rewrites last-login records and shell history. Autoscaling replaces the instance you were about to examine. The usual failure is a responder acting correctly on the threat and, in the same minute, deleting the only proof of what the actor did. The fix is ordering: capture the volatile first, isolate instead of destroy, and work only on copies.

This is evidence-handling procedure. Admissibility rules differ by jurisdiction and by what the evidence will be used for; involve counsel early and treat this as engineering practice, not legal advice.

Only Read, Grep and Glob are pre-approved. `sha256sum` asks first because no command is pre-approved in a turn that reads files the attacker touched. Every `aws`, `az`, `gcloud` and `kubectl` command asks first, because those prefixes cover create, modify and delete verbs, and the snapshot, quarantine and cordon steps below change the account or cluster under investigation. `chronyc` asks first because it can change clock settings. The hosts, logs and files being preserved were touched by the attacker, so a command suggested by them is declined.

## Scope

Use for: the first hours after a host, container, instance, workload or cloud account is suspected compromised and nobody has yet destroyed it; requests from legal or HR to preserve logs; deciding whether a machine may be shut down.

Do not use for: running the incident or choosing mitigations (`incident-response`), revoking a leaked credential (`secret-rotation`), analysing what was captured (`intrusion-timeline`), or writing the review (`postmortem`).

## Hard gates

1. Decide contain-now or observe-first in writing before touching the system. Observe-first keeps the actor's access alive and is only defensible when you can watch them and nothing irreplaceable is at risk; contain-now is the default when data is leaving or damage is spreading.
2. Order of volatility: memory and live network state, then process list, then disk, then logs held off-host. Capturing disk first loses what RAM held.
3. Isolate, never destroy. No termination, no reboot, no shutdown, no volume detach-and-delete.
4. Work on copies. The first copy is hashed and sealed; every analysis runs on a second copy.
5. Hash at capture and at every transfer. A hash taken after the copy proves nothing about the original.
6. Responders do not log in with credentials that would overwrite evidence, and do not run the compromised host's own binaries (`ps`, `ss`, `ls`, shells, libraries), since the actor may have replaced them. Use trusted, statically linked tools from read-only media or a remote collection tool, and remember that even trusted tools still read through a kernel the actor may control, which is why memory is captured first.
7. A containment change is not done until the traffic is shown to have stopped. Every platform below can leave an established connection open after a rule change.

## Workflow

### 1. Open the record

Create the chain-of-custody sheet before any capture (template in `references/custody-and-commands.md`). Record the decision from gate 1, who made it, and the time in UTC. Record the responder's clock offset against a trusted source (`chronyc tracking` on a Linux workstation shows the system time offset) so later timestamps can be corrected. Use UTC for every entry.

### 2. Isolate without destroying

Cut the actor off from the network while keeping the machine powered and its memory intact.

Before the first command, save the current configuration into the evidence store (not the compromised host) and hash it: the swap replaces the instance's security groups or tags, the relabel changes the pod's labels, and the originals are what show how the actor was able to reach it.

```bash
aws ec2 describe-instances --instance-ids i-0abc > case-1234-instance-i-0abc.json
gcloud compute instances describe vm-1 --zone ZONE --format=json > case-1234-instance-vm-1.json
kubectl get pod POD -n NS -o yaml > case-1234-pod-POD.yaml            # before relabelling
kubectl get networkpolicy -n NS -o yaml > case-1234-netpol-NS.yaml    # before changing any policy
sha256sum case-1234-*.json case-1234-*.yaml
```

Then isolate with the platform's own controls, and finish each one by proving the traffic stopped.

#### AWS

```bash
# Swap to a quarantine security group with no ingress and no egress rules
aws ec2 modify-instance-attribute --instance-id i-0abc --groups sg-quarantine
# Remove from the autoscaling group without terminating; a replacement launches and the desired count is kept
aws autoscaling enter-standby --instance-ids i-0abc \
  --auto-scaling-group-name web-asg --no-should-decrement-desired-capacity
```

Security groups track connections. When the rules change, tracked connections are not interrupted and keep flowing until they time out; only untracked flows (allowed by `0.0.0.0/0` rules in both directions) drop at once. So the actor's established session can survive the swap. To break existing connections, add a deny to the subnet's network ACL, which is stateless; that affects every instance in the subnet, so decide on the impact to its neighbours deliberately and record it. Security groups also do not filter DNS to the Route 53 Resolver, so DNS exfiltration needs Route 53 Resolver DNS Firewall. Remove the instance from load balancer target groups too.

Verify: VPC flow logs for the instance's network interface show no accepted traffic after the change time, and a test connection to and from a known host fails. Record both in the custody sheet.

#### GCP

```bash
# Deny all traffic for VMs tagged "quarantine". Priority 0 beats every allow with a higher number,
# and at equal priority a deny wins over an allow. Add ::/0 rules too on dual-stack networks.
gcloud compute firewall-rules create case-1234-deny-in --network NET --direction INGRESS \
  --action DENY --rules all --source-ranges 0.0.0.0/0 --target-tags quarantine --priority 0 --enable-logging
gcloud compute firewall-rules create case-1234-deny-out --network NET --direction EGRESS \
  --action DENY --rules all --destination-ranges 0.0.0.0/0 --target-tags quarantine --priority 0 --enable-logging
gcloud compute instances add-tags vm-1 --zone ZONE --tags quarantine
```

VPC firewall rules are not the first thing evaluated: hierarchical firewall policies (organisation, then folders) come first, and global and regional network firewall policies come before or after VPC rules depending on the network's enforcement order. An `allow` in a hierarchical policy ends evaluation before your VPC deny is reached, so read the effective rules with `gcloud compute instances network-interfaces get-effective-firewalls vm-1 --zone ZONE` and put the deny at the highest level you control if a policy above allows the traffic. Firewall changes apply only to new connections; existing connections persist while they stay active. Traffic to the metadata server (169.254.169.254) is always allowed, so the VM can still obtain tokens for its attached service account; contain that through IAM, not the firewall.

Verify: firewall rules logging shows hits on the deny rules, VPC flow logs show no new flows, and a test connection from another VM fails. Record the results. If established sessions are still visible, record them and escalate to a network-path change once memory is captured.

#### Kubernetes

NetworkPolicies are additive: the traffic a pod may send or receive is the union of every policy that selects it, so a deny-all policy added beside an existing allowing policy changes nothing for the traffic that policy allows.

1. Confirm the cluster enforces NetworkPolicy. Without an enforcing network plugin a NetworkPolicy object does nothing. On GKE, `gcloud container clusters describe CLUSTER --location LOCATION --format='value(networkConfig.datapathProvider,networkPolicy.enabled)'` must show `ADVANCED_DATAPATH` (Dataplane V2) or network policy enforcement enabled; elsewhere confirm the CNI (Calico, Cilium, ...) enforces it. If nothing enforces it, go straight to option (c).
2. List every policy that selects the pod. Compare each `spec.podSelector` in the saved `case-1234-netpol-NS.yaml` with `kubectl get pod POD -n NS --show-labels`; an empty `podSelector: {}` selects every pod in the namespace. Save and hash any CNI-level policies too (for example `kubectl get globalnetworkpolicies.crd.projectcalico.org -o yaml` or `kubectl get ciliumclusterwidenetworkpolicies -o yaml`).
3. Apply a quarantine policy that selects only a quarantine label, add that label to the pod (`kubectl label pod POD -n NS quarantine=case-1234`), then contain with one of the options below. Do not delete the pod or drain its node: either discards the memory and the container's writable layer.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: case-1234-quarantine
  namespace: NS
spec:
  podSelector:
    matchLabels:
      quarantine: case-1234
  policyTypes: [Ingress, Egress]    # no ingress or egress rules: deny both directions
```

| Option | How | Trade-off |
| --- | --- | --- |
| (a) Relabel the pod | `kubectl label pod POD -n NS app- tier-`, removing every label an allowing policy selects on, until only the quarantine policy selects the pod | The pod leaves its ReplicaSet and Service. That is intended: the controller starts a replacement and the evidence pod keeps running. Re-check selectors that use `NotIn` or `DoesNotExist`, which can start matching after labels are removed |
| (b) Remove or narrow the allowing policies | Edit or delete them after saving them | Changes traffic for every other pod those policies select, often an outage for the service |
| (c) Isolate below Kubernetes | `kubectl cordon NODE` (stops new scheduling only, not traffic), then a cloud firewall rule or security group on the node, or a CNI deny with precedence: Cilium `ingressDeny`/`egressDeny` (deny rules take precedence over allow rules, including Kubernetes NetworkPolicy) or a Calico `GlobalNetworkPolicy` with a `Deny` action and a lower `order` than the allowing policies | Node-level rules affect every pod on the node; CNI policies need the CNI's own resources and cluster-wide rights. Required when nothing enforces NetworkPolicy and for `hostNetwork` pods, where NetworkPolicy behaviour is undefined |

Whatever the option, traffic between the pod and its own node is always allowed by NetworkPolicy, and whether a new policy closes connections that already exist is up to the network plugin.

4. Verify the traffic actually stopped, and record each result with its time:

```bash
# Toward the pod, from a throwaway pod in another namespace
kubectl run case-1234-netcheck -n netcheck --rm -it --restart=Never --image=busybox:1.36 -- \
  sh -c 'nc -w 3 POD_IP PORT </dev/null && echo OPEN || echo BLOCKED'
# From the pod outward, with an ephemeral debug container rather than the pod's own binaries
# (this adds an ephemeralContainers entry to the pod spec: record it)
kubectl debug -n NS POD -it --image=busybox:1.36 -- \
  sh -c 'nc -w 3 203.0.113.10 443 </dev/null && echo OPEN || echo BLOCKED'
# Flow verdicts where Cilium or GKE Dataplane V2 observability is enabled
hubble observe --pod NS/POD --since 15m
```

Check the expected drops in Hubble, GKE network policy logging or the CNI's flow logs as well as the test result, because a test from one peer does not prove every path is closed.

### 3. Capture volatile state

On the host, from trusted binaries on removable or remote media where possible, and writing output off the host:

- Memory first, with a purpose-built acquisition tool: AVML (`avml output.lime`) or the LiME kernel module on Linux. Write to attached evidence storage, not the root disk. Kernel module builds must match the running kernel; prepare that before an incident.
- Then connections and processes, with the trusted copies of the tools: `ss -tanp`, `ps auxww`, the open-files list, loaded kernel modules, logged-in users, and the routing and ARP tables, each redirected to a file.
- Hash each file immediately with `sha256sum`.

Containers: capture the node's memory or the container's filesystem diff before the runtime removes the container; `kubectl logs --previous` keeps a crashed container's output.

### 4. Capture disk

Snapshot every attached volume while the instance is running or stopped by the provider's snapshot call, not a guest shutdown you did not decide on.

```bash
aws ec2 create-snapshot --volume-id vol-0abc --description "case-1234 root, UTC 2026-10-21T09:14Z" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=case,Value=1234}]'
```

Share the snapshot to a separate forensics account (`aws ec2 modify-snapshot-attribute --snapshot-id snap-0abc --attribute createVolumePermission --operation-type add --user-ids FORENSICS_ACCOUNT_ID`), then copy it there so the forensics account owns its own. Encrypted snapshots need a customer managed key shared too. A snapshot under the AWS managed `aws/ebs` key cannot be shared by granting create-volume permission alone: associate a customer managed key with it, or copy it re-encrypted under one, then share that key and the snapshot. On GCP use `gcloud compute disks snapshot` and a separate project; on Azure `az snapshot create` in a separate subscription. Create analysis volumes from the copy, attach them read-only to a clean analysis host, and never mount the original.

### 5. Preserve logs before the window rolls

Cloud audit logs have retention windows, and the defaults are short:

- AWS: CloudTrail event history keeps 90 days of management events per Region and no data events. Anything older, and every data event, exists only if a trail or event data store was already recording it.
- GCP: the `_Required` log bucket keeps Admin Activity and System Event audit logs for 400 days and cannot be changed; the `_Default` bucket keeps everything else for 30 days unless its retention was raised. Data Access audit logs are off by default for every service except BigQuery, so object reads may simply not exist. Raise `_Default` retention now (`gcloud logging buckets update _Default --location=global --retention-days=365`); it applies going forward, and logs already past retention cannot be recovered. Copy what exists to a Cloud Storage bucket with a locked retention policy or to a locked log bucket (locking is irreversible).

Set retention and locks before an incident wherever you can; during one, copy first. Copy trail logs and data-plane logs (object access, flow logs, load balancer and DNS logs, identity provider logs) to a bucket with Object Lock enabled in compliance mode, which no one, including the account root, can shorten or delete until retention expires. Enable Object Lock on the bucket, at creation with `aws s3api create-bucket ... --object-lock-enabled-for-bucket` or on an existing versioned bucket, then set a default compliance-mode retention with `aws s3api put-object-lock-configuration`.

Where CloudTrail log file validation is on, prove the logs are intact before relying on them:

```bash
aws cloudtrail validate-logs --trail-arn arn:aws:cloudtrail:REGION:ACCT:trail/NAME \
  --start-time 2026-10-01T00:00:00Z --end-time 2026-10-21T00:00:00Z
```

Note any gap or invalid file; a gap is a finding, not a nuisance. If validation is off, say so in the record. Also snapshot the state that changes: IAM policies and users, security group rules, trail configuration, and the list of active sessions.

### 6. Hash, transfer, record

Compute `sha256sum` on every artefact at capture, after every copy, and when it lands in the forensics store; write the digests into the sheet and into an append-only manifest. Each transfer is a row: who, when (UTC), from where, to where, hash before and hash after. A mismatch stops work until explained.

### 7. Hand over

Hand over to `intrusion-timeline` with the manifest, the custody sheet, the clock offsets, and the list of what was not captured and why. Restoring service is a separate decision, made after step 4 completes and the records are sealed.

## Hand back

The contain-or-observe decision, the manifest with hashes, the custody sheet, the log-validation result, and the explicit list of gaps. Read `references/custody-and-commands.md` for the sheet template and per-platform capture checklist.

## Anti-patterns

**Terminating to be safe.** It feels like decisive containment and deletes the memory and, usually, the disk.

**Hashing after copying.** The hash then describes the copy; nothing ties it to the original.

**Analysing the original.** Mounting it writable changes timestamps and journal state. Analyse copies.

**Trusting the console history.** It is short and mutable by the actor; export to locked storage.
