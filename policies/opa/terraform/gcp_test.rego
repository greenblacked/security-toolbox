package terraform.gcp_test

import rego.v1

import data.terraform.gcp

good := json.unmarshal(`{"resource_changes":[{"address":"google_compute_firewall.iap","type":"google_compute_firewall","change":{"actions":["create"],"after":{"source_ranges":["35.235.240.0/20"],"allow":[{"protocol":"tcp","ports":["22"]}]}}},{"address":"google_storage_bucket.b","type":"google_storage_bucket","change":{"actions":["create"],"after":{"public_access_prevention":"enforced","uniform_bucket_level_access":true,"encryption":[{"default_kms_key_name":"k"}]}}}]}`)

test_good_plan_passes if {
	count(gcp.deny) == 0 with input as good
	count(gcp.warn) == 0 with input as good
}

test_ssh_from_world_denied if {
	plan := {"resource_changes": [{
		"address": "google_compute_firewall.ssh",
		"type": "google_compute_firewall",
		"change": {"actions": ["create"], "after": {"source_ranges": ["0.0.0.0/0"], "allow": [{"protocol": "tcp", "ports": ["22"]}]}},
	}]}
	some msg in gcp.deny with input as plan
	contains(msg, "admin port 22")
}

test_port_range_covering_ssh_denied if {
	plan := {"resource_changes": [{
		"address": "google_compute_firewall.r",
		"type": "google_compute_firewall",
		"change": {"actions": ["create"], "after": {"source_ranges": ["0.0.0.0/0"], "allow": [{"protocol": "tcp", "ports": ["1-65535"]}]}},
	}]}
	count(gcp.deny) == 2 with input as plan
}

test_https_from_world_allowed if {
	plan := {"resource_changes": [{
		"address": "google_compute_firewall.https",
		"type": "google_compute_firewall",
		"change": {"actions": ["create"], "after": {"source_ranges": ["0.0.0.0/0"], "allow": [{"protocol": "tcp", "ports": ["443"]}]}},
	}]}
	count(gcp.deny) == 0 with input as plan
}

test_all_users_member_denied if {
	plan := {"resource_changes": [{
		"address": "google_storage_bucket_iam_member.p",
		"type": "google_storage_bucket_iam_member",
		"change": {"actions": ["create"], "after": {"member": "allUsers", "role": "roles/storage.objectViewer"}},
	}]}
	count(gcp.deny) == 1 with input as plan
}

test_deletes_ignored if {
	plan := {"resource_changes": [{
		"address": "google_storage_bucket.gone",
		"type": "google_storage_bucket",
		"change": {"actions": ["delete"], "after": null},
	}]}
	count(gcp.deny) == 0 with input as plan
}

test_service_account_key_denied if {
	plan := {"resource_changes": [{
		"address": "google_service_account_key.ci",
		"type": "google_service_account_key",
		"change": {"actions": ["create"], "after": {"service_account_id": "ci"}},
	}]}
	some msg in gcp.deny with input as plan
	contains(msg, "service-account keys")
}

test_public_access_prevention_not_enforced_denied if {
	plan := {"resource_changes": [{
		"address": "google_storage_bucket.b",
		"type": "google_storage_bucket",
		"change": {"actions": ["create"], "after": {"public_access_prevention": "inherited", "uniform_bucket_level_access": true}},
	}]}
	some msg in gcp.deny with input as plan
	contains(msg, "public_access_prevention")
}

fw_plan(after) := {"resource_changes": [{
	"address": "google_compute_firewall.f",
	"type": "google_compute_firewall",
	"change": {"actions": ["create"], "after": after},
}]}

world(allow) := {"source_ranges": ["0.0.0.0/0"], "allow": allow}

test_numeric_tcp_protocol_denied if {
	count(gcp.deny) == 1 with input as fw_plan(world([{"protocol": "6", "ports": ["22"]}]))
}

test_uppercase_protocol_denied if {
	count(gcp.deny) == 1 with input as fw_plan(world([{"protocol": "TCP", "ports": ["3389"]}]))
}

test_udp_rdp_denied if {
	count(gcp.deny) == 1 with input as fw_plan(world([{"protocol": "17", "ports": ["3389"]}]))
}

test_udp_22_allowed if {
	count(gcp.deny) == 0 with input as fw_plan(world([{"protocol": "udp", "ports": ["22"]}]))
}

test_sctp_all_ports_allowed if {
	count(gcp.deny) == 0 with input as fw_plan(world([{"protocol": "132"}]))
}

test_ssh_in_second_allow_block_denied if {
	allow := [{"protocol": "tcp", "ports": ["443"]}, {"protocol": "tcp", "ports": ["22"]}]
	count(gcp.deny) == 1 with input as fw_plan(world(allow))
}

test_tcp_without_ports_denied_for_both if {
	count(gcp.deny) == 2 with input as fw_plan(world([{"protocol": "tcp"}]))
}

test_protocol_all_denied_for_both if {
	count(gcp.deny) == 2 with input as fw_plan(world([{"protocol": "all"}]))
}

test_explicit_nulls_do_not_fail_open if {
	after := {"source_ranges": ["0.0.0.0/0"], "direction": null, "disabled": null, "allow": [{"protocol": "tcp", "ports": null}]}
	count(gcp.deny) == 2 with input as fw_plan(after)
}

test_disabled_and_egress_ignored if {
	disabled := object.union(world([{"protocol": "tcp", "ports": ["22"]}]), {"disabled": true})
	count(gcp.deny) == 0 with input as fw_plan(disabled)
	egress := object.union(world([{"protocol": "tcp", "ports": ["22"]}]), {"direction": "EGRESS"})
	count(gcp.deny) == 0 with input as fw_plan(egress)
}

bucket_policy_plan(after) := {"resource_changes": [{
	"address": "google_storage_bucket_iam_policy.p",
	"type": "google_storage_bucket_iam_policy",
	"change": {"actions": ["create"], "after": after},
}]}

test_bucket_iam_policy_all_users_denied if {
	pd := json.marshal({"bindings": [
		{"role": "roles/storage.admin", "members": ["group:ops@example.com"]},
		{"role": "roles/storage.objectViewer", "members": ["allUsers"]},
	]})
	plan := bucket_policy_plan({"bucket": "existing-bucket", "policy_data": pd})
	count(gcp.deny) == 1 with input as plan
	some msg in gcp.deny with input as plan
	contains(msg, "allUsers")
}

test_bucket_iam_policy_all_authenticated_users_denied if {
	pd := json.marshal({"bindings": [{"role": "roles/storage.objectViewer", "members": ["allAuthenticatedUsers"]}]})
	count(gcp.deny) == 1 with input as bucket_policy_plan({"bucket": "b", "policy_data": pd})
}

test_bucket_iam_policy_private_allowed if {
	pd := json.marshal({"bindings": [{"role": "roles/storage.objectViewer", "members": ["serviceAccount:r@example.iam.gserviceaccount.com"]}]})
	plan := bucket_policy_plan({"bucket": "b", "policy_data": pd})
	count(gcp.deny) == 0 with input as plan
	count(gcp.warn) == 0 with input as plan
}

test_bucket_iam_policy_unknown_warns if {
	plan := bucket_policy_plan({"bucket": "b"})
	count(gcp.deny) == 0 with input as plan
	count(gcp.warn) == 1 with input as plan
}

test_bucket_iam_policy_null_is_unknown if {
	some msg in gcp.warn with input as bucket_policy_plan({"bucket": "b", "policy_data": null})
	contains(msg, "not known at plan time")
}

test_bucket_iam_policy_invalid_json_has_own_warning if {
	plan := bucket_policy_plan({"bucket": "b", "policy_data": "not json"})
	count(gcp.warn) == 1 with input as plan
	some msg in gcp.warn with input as plan
	contains(msg, "not a valid IAM policy JSON object")
	not contains(msg, "not known at plan time")
}

test_bucket_iam_policy_non_object_json_warns if {
	some msg in gcp.warn with input as bucket_policy_plan({"bucket": "b", "policy_data": "[1, 2]"})
	contains(msg, "not a valid IAM policy JSON object")
}

one(type, after) := {"resource_changes": [{
	"address": sprintf("%s.r", [type]),
	"type": type,
	"change": {"actions": ["create"], "after": after},
}]}

private_lookalikes := ["group:allUsers@example.com", "user:allAuthenticatedUsers@x.com", "serviceAccount:allusers@p.iam.gserviceaccount.com"]

test_private_lookalike_member_allowed if {
	every m in private_lookalikes {
		count(gcp.deny) == 0 with input as one("google_storage_bucket_iam_member", {"member": m})
	}
}

test_private_lookalike_binding_allowed if {
	count(gcp.deny) == 0 with input as one("google_storage_bucket_iam_binding", {"members": private_lookalikes})
}

test_private_lookalike_policy_data_allowed if {
	pd := json.marshal({"bindings": [{"role": "roles/storage.objectViewer", "members": private_lookalikes}]})
	plan := bucket_policy_plan({"bucket": "b", "policy_data": pd})
	count(gcp.deny) == 0 with input as plan
	count(gcp.warn) == 0 with input as plan
}

test_public_access_control_entity_denied if {
	count(gcp.deny) == 1 with input as one("google_storage_bucket_access_control", {"entity": "allUsers", "role": "READER"})
	count(gcp.deny) == 1 with input as one("google_storage_default_object_access_control", {"entity": "allAuthenticatedUsers", "role": "READER"})
}

test_private_lookalike_access_control_entity_allowed if {
	count(gcp.deny) == 0 with input as one("google_storage_bucket_access_control", {"entity": "group-allUsers@example.com", "role": "READER"})
}

test_public_role_entity_denied if {
	plan := one("google_storage_bucket_acl", {"role_entity": ["OWNER:project-owners-123", "READER:allUsers"]})
	count(gcp.deny) == 1 with input as plan
	count(gcp.deny) == 1 with input as one("google_storage_default_object_acl", {"role_entity": ["READER:allAuthenticatedUsers"]})
}

test_private_lookalike_role_entity_allowed if {
	plan := one("google_storage_bucket_acl", {"role_entity": ["READER:group-allUsers@example.com", "READER:user-allAuthenticatedUsers@x.com"]})
	count(gcp.deny) == 0 with input as plan
}

test_null_members_do_not_error if {
	count(gcp.deny) == 0 with input as one("google_storage_bucket_iam_binding", {"members": null})
	count(gcp.deny) == 0 with input as one("google_storage_bucket_acl", {"role_entity": null})
}

# --- Full public-GCS sweep: one positive and one negative per pair -----------

denies(type, after) if count(gcp.deny) > 0 with input as one(type, after)

allows(type, after) if count(gcp.deny) == 0 with input as one(type, after)

test_bucket_acl_predefined_acl if {
	every v in ["publicRead", "publicReadWrite", "authenticatedRead"] {
		denies("google_storage_bucket_acl", {"bucket": "existing", "predefined_acl": v})
	}
	every v in ["private", "projectPrivate"] {
		allows("google_storage_bucket_acl", {"bucket": "existing", "predefined_acl": v})
	}
}

test_bucket_acl_default_acl if {
	every v in ["publicRead", "authenticatedRead"] {
		denies("google_storage_bucket_acl", {"bucket": "existing", "default_acl": v})
	}
	every v in ["private", "projectPrivate", "bucketOwnerRead", "bucketOwnerFullControl"] {
		allows("google_storage_bucket_acl", {"bucket": "existing", "default_acl": v})
	}
}

test_object_acl_predefined_acl if {
	every v in ["publicRead", "publicReadWrite", "authenticatedRead"] {
		denies("google_storage_object_acl", {"bucket": "existing", "object": "o", "predefined_acl": v})
	}
	every v in ["private", "projectPrivate", "bucketOwnerRead", "bucketOwnerFullControl"] {
		allows("google_storage_object_acl", {"bucket": "existing", "object": "o", "predefined_acl": v})
	}
}

test_predefined_acl_exact_match if {
	every v in ["publicread", "public-read", "notpublicRead", "publicReadX"] {
		allows("google_storage_bucket_acl", {"bucket": "existing", "predefined_acl": v})
	}
}

test_object_acl_role_entity if {
	denies("google_storage_object_acl", {"bucket": "existing", "object": "o", "role_entity": ["READER:allUsers"]})
	allows("google_storage_object_acl", {"bucket": "existing", "object": "o", "role_entity": ["READER:group-allUsers@example.com"]})
}

test_default_object_acl_role_entity if {
	denies("google_storage_default_object_acl", {"bucket": "existing", "role_entity": ["READER:allAuthenticatedUsers"]})
	allows("google_storage_default_object_acl", {"bucket": "existing", "role_entity": ["OWNER:project-owners-1", "READER:user-allAuthenticatedUsers@x.com"]})
}

test_access_control_entities if {
	every type in ["google_storage_bucket_access_control", "google_storage_object_access_control", "google_storage_default_object_access_control"] {
		denies(type, {"bucket": "existing", "entity": "allUsers", "role": "READER"})
		denies(type, {"bucket": "existing", "entity": "allAuthenticatedUsers", "role": "READER"})
		allows(type, {"bucket": "existing", "entity": "group-allUsers@example.com", "role": "READER"})
		allows(type, {"bucket": "existing", "entity": "project-viewers-123", "role": "READER"})
	}
}

test_managed_folder_iam if {
	denies("google_storage_managed_folder_iam_member", {"bucket": "existing", "managed_folder": "f/", "member": "allUsers"})
	allows("google_storage_managed_folder_iam_member", {"bucket": "existing", "managed_folder": "f/", "member": "group:allUsers@example.com"})
	denies("google_storage_managed_folder_iam_binding", {"bucket": "existing", "managed_folder": "f/", "members": ["allAuthenticatedUsers"]})
	allows("google_storage_managed_folder_iam_binding", {"bucket": "existing", "managed_folder": "f/", "members": ["user:allAuthenticatedUsers@x.com"]})
	public := json.marshal({"bindings": [{"role": "roles/storage.objectViewer", "members": ["allUsers"]}]})
	private := json.marshal({"bindings": [{"role": "roles/storage.objectViewer", "members": ["group:allUsers@example.com"]}]})
	denies("google_storage_managed_folder_iam_policy", {"bucket": "existing", "managed_folder": "f/", "policy_data": public})
	allows("google_storage_managed_folder_iam_policy", {"bucket": "existing", "managed_folder": "f/", "policy_data": private})
}

test_managed_folder_policy_unknown_warns if {
	count(gcp.warn) == 1 with input as one("google_storage_managed_folder_iam_policy", {"bucket": "existing", "managed_folder": "f/"})
}
