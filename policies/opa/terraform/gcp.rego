# GCP guardrails evaluated against `terraform show -json` plan output.
#
#   terraform plan -out=tfplan && terraform show -json tfplan > plan.json
#   conftest test --policy policies/opa/terraform --namespace terraform.gcp plan.json
#
# Only resources being created or updated are checked; deletes are ignored.
package terraform.gcp

import rego.v1

admin_ports := {"22", "3389"}

public_members := {"allUsers", "allAuthenticatedUsers"}

changed contains rc if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
}

# --- Firewall: no 0.0.0.0/0 ingress to admin ports -------------------------

open_to_world(fw) if "0.0.0.0/0" in fw.source_ranges

open_to_world(fw) if "::/0" in fw.source_ranges

allows_port(rule, _) if {
	rule.protocol in {"all", "tcp"}
	count(object.get(rule, "ports", [])) == 0
}

allows_port(rule, port) if {
	rule.protocol == "tcp"
	some p in rule.ports
	p == port
}

allows_port(rule, port) if {
	rule.protocol == "tcp"
	some p in rule.ports
	contains(p, "-")
	bounds := split(p, "-")
	to_number(bounds[0]) <= to_number(port)
	to_number(port) <= to_number(bounds[1])
}

deny contains msg if {
	some rc in changed
	rc.type == "google_compute_firewall"
	fw := rc.change.after
	object.get(fw, "direction", "INGRESS") == "INGRESS"
	not object.get(fw, "disabled", false)
	open_to_world(fw)
	some rule in fw.allow
	some port in admin_ports
	allows_port(rule, port)
	msg := sprintf("%s: ingress from the internet to admin port %s; use IAP TCP forwarding or a bastion range", [rc.address, port])
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
