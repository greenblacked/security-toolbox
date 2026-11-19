"""Checkov custom check: bucket IAM and ACLs must not grant allUsers or allAuthenticatedUsers.

Members are matched exactly, so a private identity such as
group:allUsers@example.com is not treated as public.

Covers google_storage_bucket_iam_member, _iam_binding and _iam_policy, and
the ACL resources (entity, or role_entity entries such as "READER:allUsers"). For
_iam_policy, policy_data is inspected when Checkov can resolve it statically:
a jsonencode(...) literal, a JSON string, or a reference to a
data.google_iam_policy in the same module (Checkov renders its binding blocks).
Anything it cannot resolve (a variable, a module output, a file() call) is
reported as UNKNOWN rather than passed; CKV_STB_GCP_5 still checks the
google_iam_policy data source where it is declared.
"""

import json

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

PUBLIC_MEMBERS = {"allUsers", "allAuthenticatedUsers"}

ACL_ENTITY_RESOURCES = (
    "google_storage_bucket_access_control",
    "google_storage_default_object_access_control",
    "google_storage_object_access_control",
)
ACL_ROLE_ENTITY_RESOURCES = (
    "google_storage_bucket_acl",
    "google_storage_default_object_acl",
    "google_storage_object_acl",
)


def _flatten(value: object) -> list[str]:
    if isinstance(value, list):
        out: list[str] = []
        for item in value:
            out.extend(_flatten(item))
        return out
    return [str(value)] if value is not None else []


def policy_bindings(policy_data: object) -> list[dict] | None:
    """Bindings from a resolved policy_data value, or None if unresolvable."""
    if isinstance(policy_data, list) and len(policy_data) == 1:
        policy_data = policy_data[0]
    if isinstance(policy_data, str):
        try:
            policy_data = json.loads(policy_data)
        except ValueError:
            return None  # an unresolved reference such as "${var.policy}"
    if not isinstance(policy_data, dict):
        return None
    # jsonencode / JSON uses "bindings"; a rendered data source uses "binding".
    bindings = policy_data.get("bindings", policy_data.get("binding"))
    if bindings is None:
        return None
    return [b for b in _flatten_dicts(bindings) if isinstance(b, dict)]


def _flatten_dicts(value: object) -> list:
    if isinstance(value, list):
        out: list = []
        for item in value:
            out.extend(_flatten_dicts(item))
        return out
    return [value]


def has_public_member(bindings: list[dict]) -> bool:
    return any(m in PUBLIC_MEMBERS for b in bindings for m in _flatten(b.get("members")))


class GCSNoPublicMembers(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="GCS bucket IAM does not grant allUsers or allAuthenticatedUsers",
            id="CKV_STB_GCP_4",
            categories=(CheckCategories.IAM,),
            supported_resources=(
                "google_storage_bucket_iam_member",
                "google_storage_bucket_iam_binding",
                "google_storage_bucket_iam_policy",
                *ACL_ENTITY_RESOURCES,
                *ACL_ROLE_ENTITY_RESOURCES,
            ),
        )

    def scan_resource_conf(self, conf: dict) -> CheckResult:
        if "policy_data" in conf:
            bindings = policy_bindings(conf["policy_data"])
            if bindings is None:
                return CheckResult.UNKNOWN
            return CheckResult.FAILED if has_public_member(bindings) else CheckResult.PASSED
        members = (
            _flatten(conf.get("member"))
            + _flatten(conf.get("members"))
            + _flatten(conf.get("entity"))
            + [entry.partition(":")[2] for entry in _flatten(conf.get("role_entity"))]
        )
        if any(m in PUBLIC_MEMBERS for m in members):
            return CheckResult.FAILED
        return CheckResult.PASSED


check = GCSNoPublicMembers()
