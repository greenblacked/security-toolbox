"""Checkov custom check: bucket IAM must not grant allUsers or allAuthenticatedUsers."""

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

PUBLIC_MEMBERS = {"allUsers", "allAuthenticatedUsers"}


def _flatten(value: object) -> list[str]:
    if isinstance(value, list):
        out: list[str] = []
        for item in value:
            out.extend(_flatten(item))
        return out
    return [str(value)] if value is not None else []


class GCSNoPublicMembers(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="GCS bucket IAM does not grant allUsers or allAuthenticatedUsers",
            id="CKV_STB_GCP_4",
            categories=(CheckCategories.IAM,),
            supported_resources=(
                "google_storage_bucket_iam_member",
                "google_storage_bucket_iam_binding",
            ),
        )

    def scan_resource_conf(self, conf: dict) -> CheckResult:
        members = _flatten(conf.get("member")) + _flatten(conf.get("members"))
        if any(m in PUBLIC_MEMBERS for m in members):
            return CheckResult.FAILED
        return CheckResult.PASSED


check = GCSNoPublicMembers()
