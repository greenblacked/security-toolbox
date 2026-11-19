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
