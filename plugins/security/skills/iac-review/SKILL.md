---
name: iac-review
description: "Review an infrastructure-as-code change against the machine-readable plan JSON rather than the human-readable plan text — blast radius and destroys first, then replacement causes, drift, state moves, secrets in state, pinning, the policy-as-code gate, cost, and a verdict. Also covers Ansible review via check mode, --diff, and idempotence. Use this skill whenever the user asks you to review, sanity-check, approve, risk-assess, or explain a Terraform or OpenTofu plan, an IaC pull request, a .tf or .tfvars diff, a tfplan or plan.json file, a backend or state change, or an Ansible playbook change — including casual phrasings like \"is this safe to apply\", \"why is it recreating my database\", or \"what will this actually do\". Do not use it for authoring new modules, debugging a provider crash, or open-ended cloud architecture advice."
allowed-tools: Bash(jq:*), Read, Grep, Glob
---

# Infrastructure-as-Code Review

A good review answers one question with evidence: *what does this destroy, and can we get it back?* Everything else is secondary.

Adapted from greenblacked/AI plugins/security/skills/iac-review. Full original workflow, blast-radius queries, state safety, pinning and verdict format are preserved for use here.

## Scope

Use for: reviewing a Terraform/OpenTofu plan or PR, assessing the risk of an apply, explaining why a resource is being replaced, auditing state-moving operations, checking pinning and policy gates.

Do not use for: writing new modules, debugging provider errors, or greenfield architecture design.

## Workflow (summary)

1. Establish trust before executing IaC (source-only review first for untrusted revisions).
2. Obtain the reviewable artefact — prefer saved plan + plan.json from a trusted pipeline.
3. Blast radius, destroys before creates. Use jq to list deletions and stateful resources.
4. Establish why (action_reason, replace_paths).
5. Drift (resource_drift, relevant_attributes).
6. State safety (moved, import, deposed).
7. Secrets and state (sensitive does not keep secrets out of state).
8. Pinning (required_version, lockfile, module SHAs).
9. Policy gate (checkov, trivy, Conftest/OPA on the bound plan).
10. Cost (infracost against the reviewed artefact).
11. Verdict: Approve / Approve with conditions / Block, with blast radius listed.

See the full SKILL.md in the AI repo for the complete jq queries and hard gates.
