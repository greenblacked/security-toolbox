package kubernetes.pod_security_test

import rego.v1

import data.kubernetes.pod_security

hardened := {
	"kind": "Deployment",
	"metadata": {"name": "web"},
	"spec": {"template": {"spec": {
		"securityContext": {"runAsNonRoot": true, "runAsUser": 65532},
		"containers": [{
			"name": "web",
			"securityContext": {"allowPrivilegeEscalation": false},
			"resources": {"limits": {"memory": "128Mi"}},
		}],
	}}},
}

test_hardened_deployment_passes if {
	count(pod_security.deny) == 0 with input as hardened
	count(pod_security.warn) == 0 with input as hardened
}

test_privileged_denied if {
	pod := json.patch(hardened, [{"op": "add", "path": "/spec/template/spec/containers/0/securityContext/privileged", "value": true}])
	count(pod_security.deny) == 1 with input as pod
}

test_container_overrides_pod_run_as_non_root if {
	pod := json.patch(hardened, [{"op": "add", "path": "/spec/template/spec/containers/0/securityContext/runAsNonRoot", "value": false}])
	some msg in pod_security.deny with input as pod
	contains(msg, "runAsNonRoot")
}

test_host_path_denied if {
	pod := json.patch(hardened, [{"op": "add", "path": "/spec/template/spec/volumes", "value": [{"name": "h", "hostPath": {"path": "/var/run"}}]}])
	some msg in pod_security.deny with input as pod
	contains(msg, "hostPath")
}

test_cronjob_is_checked if {
	cj := {
		"kind": "CronJob",
		"metadata": {"name": "c"},
		"spec": {"jobTemplate": {"spec": {"template": {"spec": {"hostNetwork": true, "containers": []}}}}},
	}
	count(pod_security.deny) == 1 with input as cj
}

test_other_kinds_ignored if {
	count(pod_security.deny) == 0 with input as {"kind": "ConfigMap", "metadata": {"name": "x"}}
}

privileged_pod(metadata) := {
	"kind": "Pod",
	"metadata": metadata,
	"spec": {
		"securityContext": {"runAsNonRoot": true},
		"containers": [{
			"name": "c",
			"securityContext": {"privileged": true, "allowPrivilegeEscalation": false},
			"resources": {"limits": {"memory": "64Mi"}},
		}],
	},
}

test_generate_name_used_when_name_missing if {
	some msg in pod_security.deny with input as privileged_pod({"generateName": "job-run-"})
	startswith(msg, "Pod/job-run-: ")
}

test_unnamed_still_reported if {
	some msg in pod_security.deny with input as privileged_pod({})
	startswith(msg, "Pod/<unnamed>: ")
}
