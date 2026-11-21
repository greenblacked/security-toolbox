# Terraform GCP policy

The OPA / Conftest policy evaluates Terraform plan JSON for service-account keys, public Cloud Storage grants, bucket settings and internet-exposed SSH or RDP. It warns on buckets without CMEK.

## Run

```bash
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
conftest test --policy policies/opa/terraform --namespace terraform.gcp plan.json
```

Review plan data as sensitive. Unknown values and coverage limitations are described in the [policy coverage table](/policies/#public-gcs-coverage).

[All policies](/policies/) · [Terraform guide](/terraform/)
