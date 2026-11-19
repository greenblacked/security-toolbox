# Security Policy

## Reporting a vulnerability

Open a private security advisory rather than a public issue.

Include the check or policy, the command you ran, and what happened.

This is a personal collection of checks and policies, not a supported product. There is no formal response window.

## What matters most here

- A check that reports false negatives on known misconfigurations.
- A policy that fails open or that can be bypassed unintentionally.
- Any secret that ends up in logs or on disk.

Run reports in dry-run / read-only mode first.
