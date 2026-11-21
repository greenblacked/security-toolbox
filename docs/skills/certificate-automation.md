# Certificate Automation

Inventory certificates and automate issuance and renewal.

## Workflow

1. Inventory externally visible certificates and reconcile them with internal records. Assign an owner and renewal path to every endpoint.
2. Classify each endpoint by its available automation: native ACME, cert-manager, cloud-managed certificates or a manual-only appliance.
3. Automate issuance and renewal where supported, using ACME Renewal Information where available and an appropriate lifetime-based backstop. Plan a replacement or owned manual process for unsupported systems.
4. Monitor renewal failures and endpoint certificate expiry independently. Test failure handling, deployment of the renewed certificate and recovery before relying on the automation.

## Expected output and validation

An owned certificate inventory, endpoint classification, renewal schedule, monitoring and remaining manual risks. Verify the certificate actually served by the endpoint after renewal.

## Related resources

[Browse all security skills](/skills/) · [Hardening guides](/#guides)
