"""Checkov custom check: no SSH or RDP ingress from the internet on GCP firewalls.

Evaluates every allow block and its effective ports, matching the OPA policy in
policies/opa/terraform/gcp.rego:

- protocol names or IP protocol numbers, any case (tcp/6, udp/17, sctp/132, all);
- single ports and ranges such as "20-25" or "1-65535";
- an allow block with no ports (or protocol "all") allows every port.

Admin services: 22/tcp, 3389/tcp and 3389/udp.
"""

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

ADMIN_PORTS = {(22, "tcp"), (3389, "tcp"), (3389, "udp")}
WORLD = {"0.0.0.0/0", "::/0"}
PROTOCOL_NAMES = {"6": "tcp", "17": "udp", "132": "sctp"}


def _unwrap(value: object, default: object = None) -> object:
    """HCL attributes arrive wrapped in a single-element list."""
    if isinstance(value, list) and len(value) == 1:
        return value[0]
    if value is None or value == []:
        return default
    return value


def _as_list(value: object) -> list:
    value = _unwrap(value, [])
    if isinstance(value, list):
        return value
    return [value]


def _protocol(block: dict) -> str:
    raw = str(_unwrap(block.get("protocol"), "")).strip().lower()
    return PROTOCOL_NAMES.get(raw, raw)


def _port_matches(ports: list, port: int) -> bool:
    if not ports:
        return True
    for entry in ports:
        text = str(entry).strip()
        try:
            if "-" in text:
                low, high = (int(part) for part in text.split("-", 1))
                if low <= port <= high:
                    return True
            elif int(text) == port:
                return True
        except ValueError:
            continue  # unresolved variable or malformed entry
    return False


def exposed_admin_ports(conf: dict) -> set[int]:
    """Admin ports this firewall exposes to the internet, empty if none."""
    direction = str(_unwrap(conf.get("direction"), "INGRESS")).upper()
    if direction != "INGRESS" or _unwrap(conf.get("disabled"), False) is True:
        return set()
    if not WORLD.intersection(str(r) for r in _as_list(conf.get("source_ranges"))):
        return set()
    exposed: set[int] = set()
    for block in conf.get("allow") or []:
        if not isinstance(block, dict):
            continue
        protocol = _protocol(block)
        ports = _as_list(block.get("ports"))
        for port, transport in ADMIN_PORTS:
            if protocol in ("all", transport) and _port_matches(ports, port):
                exposed.add(port)
    return exposed


class GCPFirewallAdminPorts(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="GCP firewall does not open SSH or RDP to 0.0.0.0/0 or ::/0",
            id="CKV_STB_GCP_2",
            categories=(CheckCategories.NETWORKING,),
            supported_resources=("google_compute_firewall",),
        )

    def scan_resource_conf(self, conf: dict) -> CheckResult:
        if exposed_admin_ports(conf):
            return CheckResult.FAILED
        return CheckResult.PASSED


check = GCPFirewallAdminPorts()
