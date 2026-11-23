# Hands-on security labs

Practice a security control, capture evidence, and verify the result. All exercises use local fixtures.

| Lab | Experience | Time | Requirements |
| --- | --- | ---: | --- |
| [Threat model to backlog](threat-model.md) | Introductory | 35 min | Text editor |
| [GKE configuration review](gke-configuration.md) | Introductory | 30 min | Bash, jq |
| [Terraform policy gate](terraform-policy.md) | Intermediate | 45 min | Conftest |
| [Kubernetes workload review](kubernetes-workload.md) | Intermediate | 40 min | Bash, jq |
| [CI identity claims](ci-identity.md) | Intermediate | 40 min | Node.js |
| [Artifact provenance gate](artifact-provenance.md) | Intermediate | 55 min | Bash, jq, npm, OpenSSL |
| [Dependency remediation queue](dependency-triage.md) | Introductory | 40 min | Text editor |
| [API authorization and tenant isolation](api-authorization.md) | Intermediate | 30 min | Python |
| [Detection rule regression](detection-regression.md) | Intermediate | 45 min | Node.js |

Start with the threat model to practice deciding what evidence to collect. Continue with a configuration or policy check, then use the detection exercise to practice validation on synthetic telemetry. The [security operations flow](/start/) connects the exercises to incident and control ownership.

## Incident response path

Follow one fictional incident from telemetry through triage and recovery.

| Lab | Experience | Time | Requirements |
| --- | --- | ---: | --- |
| [Telemetry health and incident timeline](response-timeline.md) | Intermediate | 30 min | Python |
| [Incident triage and evidence custody](evidence-custody.md) | Intermediate | 35 min | Bash, Python |
| [Service restore and recovery objectives](service-restore.md) | Intermediate | 30 min | Python with SQLite |

## Get the lab kit

[Download the offline lab kit](/labs/security-toolbox-labs.tar.gz). From your download folder, extract it into a fresh directory and run the lab commands there.

```bash
mkdir security-toolbox-labs
tar -xzf security-toolbox-labs.tar.gz -C security-toolbox-labs
cd security-toolbox-labs
```

The estimates exclude tool installation. The exercises need no cluster or cloud account and create no billable cloud resources. Use synthetic inputs and use a fresh copy of the kit for experiments.
