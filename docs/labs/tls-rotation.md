# Verify TLS certificate rotation

Prove the approved certificate is the one clients receive after a service reload. Allow 30 minutes. Use Python 3.11 or later, OpenSSL 3.x, and the [lab kit](/labs/#get-the-lab-kit).

## Run the exercise

From the extracted kit, run:

```bash
python3 labs/tls-rotation.py
```

The lab generates a temporary root, intermediate and several leaves. It starts a loopback-only listener and connects with the synthetic DNS name `orders.example.test` as SNI and the expected service identity. No DNS lookup or system trust-store change is required. The client trusts only the supplied root, checks the DNS SAN and server purpose, and reads a small readiness response.

## Read the evidence

| Case | Expected result |
| --- | --- |
| New certificate on disk, old certificate served | Valid handshake, stale fingerprint |
| New certificate loaded by the same listener | Valid handshake and expected fingerprint |
| Certificate inside the 45-day exercise buffer | Valid handshake, insufficient lifetime |
| Missing intermediate or untrusted issuer | TLS verification rejected |
| Wrong DNS SAN or client-only purpose | TLS verification rejected |

The script exits unsuccessfully if an expected outcome changes. The 45-day buffer is an exercise threshold. Set your own threshold from certificate lifetime, renewal timing and remediation lead time.

For a planned service rollout, check the served chain and exact DNS name on fresh connections using the intended trust roots. Verify each relevant TLS termination path and application readiness. If the platform intentionally serves more than one valid leaf, compare with the approved set for that path. Use the fingerprint as deployment evidence and keep normal trust verification in place. A compromised private key calls for a fresh keypair and revocation of the affected certificate.

The lab closes its listener and deletes generated certificates and keys when it finishes. See [Certificate Automation](/skills/certificate-automation/), [RFC 9525](https://www.rfc-editor.org/rfc/rfc9525.html), and [NIST TLS certificate management](https://csrc.nist.gov/pubs/sp/1800/16/final).
