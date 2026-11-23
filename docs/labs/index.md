# Hands-on security labs

Practice a security control, capture evidence, and verify the result. All exercises in this catalog use local fixtures. Run commands from the repository root after cloning [Security Toolbox](https://github.com/greenblacked/security-toolbox).

| Lab | Experience | Time | Requirements |
| --- | --- | ---: | --- |
| [Threat model to backlog](threat-model.md) | Introductory | 35 min | Text editor |
| [GKE configuration review](gke-configuration.md) | Introductory | 30 min | Bash, jq |
| [Terraform policy gate](terraform-policy.md) | Intermediate | 45 min | Conftest |
| [Kubernetes workload review](kubernetes-workload.md) | Intermediate | 40 min | Bash, jq |
| [CI identity claims](ci-identity.md) | Intermediate | 40 min | Node.js |
| [Artifact provenance gate](artifact-provenance.md) | Intermediate | 55 min | Bash, jq, npm, OpenSSL |
| [Dependency remediation queue](dependency-triage.md) | Introductory | 40 min | Text editor |
| [Detection rule regression](detection-regression.md) | Intermediate | 45 min | Node.js |

Start with the threat model to practice deciding what evidence to collect. Continue with a configuration or policy check, then use the detection exercise to practice validation on synthetic telemetry. The [security operations flow](/start/) connects the exercises to incident and control ownership.

The estimates exclude tool installation. The exercises need no cluster or cloud account and create no billable cloud resources. Use synthetic inputs and keep your working copies outside the repository.
