"""Checkov custom check: data.google_iam_policy must not grant public members.

google_iam_policy builds the policy_data that *_iam_policy resources apply
authoritatively. Checking the data source itself catches public grants even
when the consuming resource is in another module and CKV_STB_GCP_4 cannot
resolve its policy_data.
"""

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.data.base_check import BaseDataCheck

PUBLIC_MEMBERS = {"allUsers", "allAuthenticatedUsers"}


def _flatten(value: object) -> list[str]:
    if isinstance(value, list):
        out: list[str] = []
        for item in value:
            out.extend(_flatten(item))
        return out
    return [str(value)] if value is not None else []


class GCPIamPolicyNoPublicMembers(BaseDataCheck):
    def __init__(self) -> None:
        super().__init__(
            name="google_iam_policy does not grant allUsers or allAuthenticatedUsers",
            id="CKV_STB_GCP_5",
            categories=(CheckCategories.IAM,),
            supported_data=("google_iam_policy",),
        )

    def scan_data_conf(self, conf: dict) -> CheckResult:
        for binding in conf.get("binding") or []:
            if isinstance(binding, dict) and any(
                m in PUBLIC_MEMBERS for m in _flatten(binding.get("members"))
            ):
                return CheckResult.FAILED
        return CheckResult.PASSED


check = GCPIamPolicyNoPublicMembers()
