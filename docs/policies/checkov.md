# Checkov GCP checks

The custom Terraform HCL checks cover public access prevention, internet-exposed SSH/RDP, service-account keys and public Cloud Storage IAM or ACL grants. Some references cannot be resolved statically and are reported as unknown.

## Run

```bash
checkov -d infra/ --external-checks-dir policies/checkov/checks
```

Compare engine coverage and limitations in the [public GCS coverage table](/policies/#public-gcs-coverage). For resolved values, also evaluate the [Terraform plan policy](/policies/terraform/).
