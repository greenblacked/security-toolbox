# Pod-level guardrails for Kubernetes manifests (Pod, Deployment,
# StatefulSet, DaemonSet, ReplicaSet, Job, CronJob).
#
#   conftest test --policy policies/opa/kubernetes --namespace kubernetes.pod_security manifests/
#
# These follow the Pod Security Standards "baseline" and "restricted" profiles
# and the "Pod Security Standards" section (5.2) of the CIS Kubernetes
# Benchmark. Item numbers inside 5.2 change between benchmark versions, so
# messages name the control topic rather than a number.
package kubernetes.pod_security

import rego.v1

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"}

pod_spec := input.spec if input.kind == "Pod"

pod_spec := input.spec.template.spec if input.kind in workload_kinds

pod_spec := input.spec.jobTemplate.spec.template.spec if input.kind == "CronJob"

# Fall back to generateName so a missing name never drops findings.
display_name := n if {
	n := object.get(input, ["metadata", "name"], "")
	n != ""
} else := n if {
	n := object.get(input, ["metadata", "generateName"], "")
	n != ""
} else := "<unnamed>"

name := sprintf("%s/%s", [input.kind, display_name])

containers contains c if {
	some field in ["initContainers", "containers", "ephemeralContainers"]
	some c in object.get(pod_spec, field, [])
}

pod_sc := object.get(pod_spec, "securityContext", {})

# Container setting wins over the pod-level default.
effective(c, key) := c.securityContext[key]

effective(c, key) := pod_sc[key] if not key in object.keys(object.get(c, "securityContext", {}))

is_set(c, key, value) if effective(c, key) == value

deny contains msg if {
	some c in containers
	is_set(c, "privileged", true)
	msg := sprintf("%s: container %q is privileged (CIS 5.2: minimise privileged containers)", [name, c.name])
}

deny contains msg if {
	some key in ["hostPID", "hostIPC", "hostNetwork"]
	pod_spec[key] == true
	msg := sprintf("%s: %s is true (CIS 5.2: minimise sharing of host namespaces)", [name, key])
}

deny contains msg if {
	some v in object.get(pod_spec, "volumes", [])
	v.hostPath
	msg := sprintf("%s: volume %q mounts a hostPath (CIS 5.2: minimise HostPath volumes)", [name, v.name])
}

deny contains msg if {
	some c in containers
	not is_set(c, "allowPrivilegeEscalation", false)
	msg := sprintf("%s: container %q must set allowPrivilegeEscalation: false (CIS 5.2: minimise privilege escalation)", [name, c.name])
}

deny contains msg if {
	some c in containers
	not is_set(c, "runAsNonRoot", true)
	msg := sprintf("%s: container %q must set runAsNonRoot: true (CIS 5.2: minimise root containers)", [name, c.name])
}

deny contains msg if {
	some c in containers
	is_set(c, "runAsUser", 0)
	msg := sprintf("%s: container %q sets runAsUser: 0 (CIS 5.2: minimise root containers)", [name, c.name])
}

deny contains msg if {
	some c in containers
	some cap in object.get(object.get(object.get(c, "securityContext", {}), "capabilities", {}), "add", [])
	upper(cap) in {"SYS_ADMIN", "NET_ADMIN", "ALL", "NET_RAW"}
	msg := sprintf("%s: container %q adds capability %s (CIS 5.2: minimise added capabilities)", [name, c.name, cap])
}

warn contains msg if {
	some c in containers
	some p in object.get(c, "ports", [])
	p.hostPort
	msg := sprintf("%s: container %q uses hostPort %d (CIS 5.2: minimise HostPorts)", [name, c.name, p.hostPort])
}

warn contains msg if {
	some c in containers
	not c.resources.limits.memory
	msg := sprintf("%s: container %q has no memory limit", [name, c.name])
}
