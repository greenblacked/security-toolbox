"""Checkov custom check: GCS IAM and ACLs must not grant allUsers or allAuthenticatedUsers.

Members, entities and predefined ACL names are matched exactly, so a private
identity such as group:allUsers@example.com is not treated as public.

Covers bucket and managed-folder IAM (member, members, policy_data), ACL
entities, role_entity entries such as "READER:allUsers", and the predefined
ACLs publicRead / publicReadWrite / authenticatedRead on google_storage_bucket_acl
(predefined_acl, default_acl) and google_storage_object_acl (predefined_acl).
The full coverage table is in policies/README.md. For *_iam_policy,
policy_data is inspected when Checkov can resolve it statically:
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

# Predefined ACLs that grant allUsers or allAuthenticatedUsers; private,
# projectPrivate, bucketOwnerRead and bucketOwnerFullControl are private.
PUBLIC_PREDEFINED_ACLS = {"publicRead", "publicReadWrite", "authenticatedRead"}

# Resource type -> attributes holding a predefined ACL name. default_acl sets
# the bucket's predefined default object ACL.
PREDEFINED_ACL_ATTRIBUTES = {
    "google_storage_bucket_acl": ("predefined_acl", "default_acl"),
    "google_storage_object_acl": ("predefined_acl",),
}

IAM_RESOURCES = (
    "google_storage_bucket_iam_member",
    "google_storage_bucket_iam_binding",
    "google_storage_bucket_iam_policy",
    "google_storage_managed_folder_iam_member",
    "google_storage_managed_folder_iam_binding",
    "google_storage_managed_folder_iam_policy",
)

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
            name="GCS IAM and ACLs do not grant allUsers or allAuthenticatedUsers",
            id="CKV_STB_GCP_4",
            categories=(CheckCategories.IAM,),
            supported_resources=(
                *IAM_RESOURCES,
                *ACL_ENTITY_RESOURCES,
                *ACL_ROLE_ENTITY_RESOURCES,
            ),
        )

    def scan_resource_conf(self, conf: dict) -> CheckResult:
        # entity_type is set by Checkov before scanning; fall back to every
        # predefined-ACL attribute when called directly (tests).
        resource_type = getattr(self, "entity_type", None)
        attributes = PREDEFINED_ACL_ATTRIBUTES.get(resource_type) or (
            "predefined_acl",
            "default_acl",
        )
        for attribute in attributes:
            if any(v in PUBLIC_PREDEFINED_ACLS for v in _flatten(conf.get(attribute))):
                return CheckResult.FAILED
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
