# Host Hardening

Harden a Linux host against a named baseline without losing access.

## Workflow

1. Name the host, operating system and baseline. Inventory effective SSH, sudo, services, firewall, audit configuration and patch status.
2. Prove a separate access path and save restorable configuration before changing access controls. Write the rollback procedure and select a canary.
3. Apply one class of change at a time: patching, accounts and SSH, kernel settings, services, file permissions, logging and firewall as applicable to the host.
4. Open a new connection to verify access, check service health and logs, and observe the canary through a representative workload cycle before expanding rollout.

## Expected output and validation

Baseline findings, saved configuration, canary changes, independent access and service checks, rollback instructions, owned exceptions and a drift-monitoring plan.

## Related resources

[Browse all security skills](/skills/) · [Hardening guides](/#guides)
