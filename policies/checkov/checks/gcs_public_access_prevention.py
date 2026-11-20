"""Checkov custom check: GCS buckets must enforce public access prevention.

Run with:
    checkov -d <terraform dir> --external-checks-dir policies/checkov/checks
"""

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck


class GCSPublicAccessPrevention(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="GCS bucket sets public_access_prevention = enforced",
            id="CKV_STB_GCP_1",
            categories=(CheckCategories.GENERAL_SECURITY,),
            supported_resources=("google_storage_bucket",),
        )

    def scan_resource_conf(self, conf: dict) -> CheckResult:
        value = conf.get("public_access_prevention", [None])
        if isinstance(value, list):
            value = value[0] if value else None
        return CheckResult.PASSED if value == "enforced" else CheckResult.FAILED


check = GCSPublicAccessPrevention()
