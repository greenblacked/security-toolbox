# GCP guardrails evaluated against `terraform show -json` plan output.
#
#   terraform plan -out=tfplan && terraform show -json tfplan > plan.json
#   conftest test --policy policies/opa/terraform --namespace terraform.gcp plan.json
#
# Only resources being created or updated are checked; deletes are ignored.
package terraform.gcp

import rego.v1

# Admin services and the transport they listen on. RDP also uses UDP 3389.
admin_ports := {
	{"port": 22, "protocol": "tcp"},
	{"port": 3389, "protocol": "tcp"},
	{"port": 3389, "protocol": "udp"},
}

public_members := {"allUsers", "allAuthenticatedUsers"}

changed contains rc if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
}

# --- Firewall: no 0.0.0.0/0 ingress to admin ports -------------------------

# Plan JSON can carry explicit nulls; treat null like an absent attribute.
attr(obj, key, fallback) := fallback if {
	object.get(obj, key, null) == null
}

attr(obj, key, _) := obj[key] if {
	obj[key] != null
}

open_to_world(fw) if "0.0.0.0/0" in attr(fw, "source_ranges", [])

open_to_world(fw) if "::/0" in attr(fw, "source_ranges", [])

# The provider accepts names or IP protocol numbers, in any case.
protocol_names := {"6": "tcp", "17": "udp", "132": "sctp"}

normalised_protocol(rule) := object.get(protocol_names, p, p) if {
	p := lower(sprintf("%v", [attr(rule, "protocol", "")]))
}

protocol_matches(rule, _) if normalised_protocol(rule) == "all"

protocol_matches(rule, protocol) if normalised_protocol(rule) == protocol

# No ports (or protocol "all") means every port.
port_matches(rule, _) if count(attr(rule, "ports", [])) == 0

port_matches(rule, port) if {
	some p in attr(rule, "ports", [])
	not contains(p, "-")
	to_number(trim_space(p)) == port
}

port_matches(rule, port) if {
	some p in attr(rule, "ports", [])
	bounds := split(p, "-")
	count(bounds) == 2
	to_number(trim_space(bounds[0])) <= port
	port <= to_number(trim_space(bounds[1]))
}

exposes(rule, admin) if {
	protocol_matches(rule, admin.protocol)
	port_matches(rule, admin.port)
}

deny contains msg if {
	some rc in changed
	rc.type == "google_compute_firewall"
	fw := rc.change.after
	attr(fw, "direction", "INGRESS") == "INGRESS"
	attr(fw, "disabled", false) != true
	open_to_world(fw)
	some rule in attr(fw, "allow", [])
	some admin in admin_ports
	exposes(rule, admin)
	msg := sprintf("%s: ingress from the internet to admin port %d; use IAP TCP forwarding or a bastion range", [rc.address, admin.port])
}

# --- GCS: no public access --------------------------------------------------

deny contains msg if {
	some rc in changed
	rc.type in {"google_storage_bucket_iam_member", "google_storage_bucket_access_control"}
	member := object.get(rc.change.after, "member", object.get(rc.change.after, "entity", ""))
	some p in public_members
	contains(member, p)
	msg := sprintf("%s: grants %s on a bucket", [rc.address, member])
}

deny contains msg if {
	some rc in changed
	rc.type == "google_storage_bucket_iam_binding"
	some member in rc.change.after.members
	member in public_members
	msg := sprintf("%s: binding includes %s", [rc.address, member])
}

# google_storage_bucket_iam_policy replaces the whole bucket policy; its
# policy_data is a JSON string (usually data.google_iam_policy.x.policy_data).
bucket_policy_bindings(rc) := bindings if {
	pd := attr(rc.change.after, "policy_data", "")
	is_string(pd)
	json.is_valid(pd)
	policy := json.unmarshal(pd)
	is_object(policy)
	bindings := attr(policy, "bindings", [])
}

deny contains msg if {
	some rc in changed
	rc.type == "google_storage_bucket_iam_policy"
	some binding in bucket_policy_bindings(rc)
	some member in attr(binding, "members", [])
	member in public_members
	msg := sprintf("%s: policy_data grants %s %s on bucket %v", [rc.address, member, object.get(binding, "role", "?"), object.get(rc.change.after, "bucket", "?")])
}

# policy_data unknown until apply (or not valid JSON) cannot be verified here.
warn contains msg if {
	some rc in changed
	rc.type == "google_storage_bucket_iam_policy"
	not bucket_policy_bindings(rc)
	msg := sprintf("%s: policy_data is not known at plan time; review it for allUsers / allAuthenticatedUsers", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type == "google_storage_bucket"
	object.get(rc.change.after, "public_access_prevention", "inherited") != "enforced"
	msg := sprintf("%s: set public_access_prevention = \"enforced\"", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type == "google_storage_bucket"
	not rc.change.after.uniform_bucket_level_access
	msg := sprintf("%s: set uniform_bucket_level_access = true so ACLs cannot reopen it", [rc.address])
}

# --- Encryption: prefer CMEK on buckets (warning, not a block) -------------

warn contains msg if {
	some rc in changed
	rc.type == "google_storage_bucket"
	count(object.get(rc.change.after, "encryption", [])) == 0
	msg := sprintf("%s: no customer-managed encryption key (encryption.default_kms_key_name)", [rc.address])
}

# --- IAM: no user-managed service-account keys -----------------------------

deny contains msg if {
	some rc in changed
	rc.type == "google_service_account_key"
	msg := sprintf("%s: user-managed service-account keys are long-lived credentials; use Workload Identity Federation or attached service accounts", [rc.address])
}
