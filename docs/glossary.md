# Glossary

**Who this is for:** anyone reading a guide here who has met one of these terms in a different context. Each row links to the page that explains it properly.

The terms these guides use, in the sense they use them, each linked to the page that explains it. The second table covers the pairs that are most often confused with each other, because getting one of them wrong usually means implementing the wrong control.

| Term | What it means here | Where |
| --- | --- | --- |
| **Admission controller** | Code in the API server path that can reject a request before the object is stored. Pod Security Admission and policy engines such as Kyverno and Gatekeeper are admission controllers. | [Kubernetes](/kubernetes/) |
| **Audit log** | The record of who called which API, when and from where. In Google Cloud, Admin Activity is always on and Data Access is off by default. | [GCP](/gcp/) |
| **Binary Authorization** | GKE admission control that admits only images matching a policy, usually attestations produced by your build. | [Kubernetes](/kubernetes/) |
| **Break-glass** | An identity or role held for emergencies and monitored rather than removed. It exists because removing standing admin and keeping no way back is its own outage. | [Access Review](/skills/access-review/) |
| **CMEK** | Customer-managed encryption key: a Cloud KMS key you control, so revoking the key makes the data unreadable. | [GCP](/gcp/) |
| **Conftest** | A CLI that evaluates OPA/Rego policies against structured files such as Terraform plan JSON or rendered manifests. | [Policies](/policies/) |
| **Deny policy** | An IAM policy that subtracts permissions and is evaluated before any allow. Use it for operations that must never happen, not as a substitute for least privilege. | [GCP](/gcp/) |
| **Digest** | The content hash of an artifact, such as `sha256:...`. A tag can be moved to different content; a digest cannot. | [Kubernetes](/kubernetes/) |
| **Envelope encryption** | Encrypting data with a data key, and the data key with a KMS key. Access is then decided by permissions on the key, which are revocable in one place. | [Secrets](/secrets/) |
| **Ephemeral resource** | A Terraform object that exists for one operation and is never written to state or plan files. | [Terraform](/terraform/) |
| **IAM condition** | An expression that narrows a role binding by time, resource name or request attribute. | [GCP](/gcp/) |
| **Least privilege** | Granting the smallest set of permissions that lets the task succeed, then removing what is left over. | [Access Review](/skills/access-review/) |
| **OIDC** | OpenID Connect. A workload or CI job presents a signed token and exchanges it for short-lived cloud credentials, so no key is stored. | [GitHub Actions](/github/) |
| **OPA / Rego** | Open Policy Agent and its policy language, used here for Terraform plan and manifest rules. | [Policies](/policies/) |
| **Pod Security Admission** | Built-in Kubernetes admission that applies one of three Pod Security Standards profiles to a namespace. | [Kubernetes](/kubernetes/) |
| **Pod Security Standards** | The three Kubernetes profiles — privileged, baseline and restricted — that Pod Security Admission enforces. | [Kubernetes](/kubernetes/) |
| **Principal Access Boundary** | A policy attached to a principal set that caps what that principal may reach, regardless of the roles granted to it. | [GCP](/gcp/) |
| **Provenance** | A signed record of how, where and from which source an artifact was built. It answers "did this come from our pipeline" without trusting the registry. | [GitHub Actions](/github/) |
| **RBAC** | Kubernetes role-based access control: which principal may perform which verb on which resource. | [Kubernetes](/kubernetes/) |
| **SBOM** | Software bill of materials: the list of components in an artifact, with versions. It tells you what is inside; it does not tell you whether it is safe. | [Dependency Triage](/skills/dependency-triage/) |
| **Secret version** | An immutable revision of a secret. Consumers either pin a version or read the latest deliberately, and a rotation adds a version rather than editing one. | [Secrets](/secrets/) |
| **Service account** | A non-human identity. A key for one is a long-lived credential; an attached or federated identity is not. | [GCP](/gcp/) |
| **SLSA** | A supply-chain integrity framework with numbered levels describing how much a consumer can verify about how an artifact was built. | [GitHub Actions](/github/) |
| **Supply chain** | Everything between source and running artifact: dependencies, build system, registry, signature and the path that verifies it. | [Dependency Triage](/skills/dependency-triage/) |
| **Terraform state** | The mapping between configuration and real resources. It holds every attribute of every managed resource, including generated secrets. | [Terraform](/terraform/) |
| **VPC Service Controls** | A Google Cloud perimeter that blocks data movement even for a principal that holds the permission. | [GCP](/gcp/) |
| **Workload Identity Federation** | Letting an external identity — a Kubernetes service account, a CI job — act as a cloud service account without a downloaded key. | [Kubernetes](/kubernetes/) |
| **Write-only argument** | A Terraform argument that passes a value to the provider and never persists it in state. | [Terraform](/terraform/) |

## Terms that are easy to confuse

| Pair | The difference |
| --- | --- |
| Authentication / authorisation | Authentication proves who is calling. Authorisation decides what they may do, on which object. A route guard does the first; it cannot do the second. |
| Pod Security Standards / Pod Security Admission | The Standards are the three profiles. Admission is the mechanism that enforces one on a namespace. |
| Image tag / image digest | A tag is a mutable name. A digest is the content. Pinning to a tag is not pinning. |
| Secret / encrypted value | Encryption protects data at rest. A secret store adds access control, versioning and an audit trail. A Kubernetes Secret is neither encrypted nor audited by default. |
| SBOM / vulnerability scan | An SBOM lists components. A scan compares those components against advisories. Neither reaches the code path that calls the component. |
| Terraform plan / Terraform apply | The plan is a proposal against the state Terraform last saw. The apply is what happens against the world as it is now. |

[Start here](/start/) · [Checks](/checks/) · [Policies](/policies/)
