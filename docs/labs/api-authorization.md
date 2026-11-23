# API authorization and tenant isolation

Verify which identities can read and change a resource. Allow 30 minutes. Use Python 3.11 or later and the [offline lab kit](/labs/#get-the-lab-kit).

## Run the access matrix

From the extracted kit, run:

```bash
python3 labs/api-authorization.py
```

The in-memory order service receives an authenticated principal from the exercise fixture. Every operation checks the principal's tenant and ownership before returning the resource or applying a change. Cancellation also checks permission to update.

| Scenario | Read | Cancel | Evidence |
| --- | --- | --- | --- |
| Owner with update permission | 200 | 204 | Owner reads the new status |
| Owner with read-only permission | 200 | 403 | Status is still open |
| Same tenant, different owner | 404 | 404 | Owner's status is still open |
| Different tenant | 404 | 404 | Other tenant's order is unchanged |
| Unknown order | 404 | 404 | Same response shape as an inaccessible order |

## Verify your service contract

The four tests should pass. In a working copy, add a test for a principal with the same user ID as the owner but a different tenant. Both operations should be denied, and the actual owner should still read the original status.

The exercise uses HTTP status values as a service contract. A production API must obtain the principal from its verified authentication context, enforce policy for each operation, and verify the same outcomes through the actual HTTP handlers and datastore. This lab starts no listener and stores all state in memory. Delete your working copy after the exercise.

Related reading: [OWASP API Security on object-level authorization](https://api-security.owasp.org/editions/2023/en/0xa1-broken-object-level-authorization/) and [Threat model to backlog](/labs/threat-model/).
