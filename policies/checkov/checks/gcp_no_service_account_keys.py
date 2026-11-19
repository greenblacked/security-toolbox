"""Checkov custom check: no user-managed GCP service-account keys.

Keys are long-lived, exportable credentials. Use Workload Identity Federation
(GitHub OIDC, GKE Workload Identity) or attached service accounts instead.
"""

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck


class GCPNoServiceAccountKeys(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="No user-managed google_service_account_key resources",
            id="CKV_STB_GCP_3",
            categories=(CheckCategories.IAM,),
            supported_resources=("google_service_account_key",),
        )

    def scan_resource_conf(self, conf: dict) -> CheckResult:
        return CheckResult.FAILED


check = GCPNoServiceAccountKeys()
