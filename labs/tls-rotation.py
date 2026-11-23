"""Verify a TLS rotation with disposable certificates and a loopback-only service."""

import hashlib
import json
import shutil
import socket
import ssl
import subprocess
from concurrent.futures import ThreadPoolExecutor
from contextlib import suppress
from pathlib import Path
from tempfile import TemporaryDirectory
from time import time

HOST = "orders.example.test"
BUFFER_SECONDS = 45 * 86400
READY = b"ready\n"


def run_openssl(binary, *args):
    # All arguments are fixed lab values or paths under the temporary directory.
    subprocess.run([binary, *args], check=True, capture_output=True)  # noqa: S603


def issue(binary, directory, name, days, extensions, issuer=None):
    cert = directory / f"{name}.pem"
    key = directory / f"{name}.key"
    common = ("-new", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-subj", f"/CN={name}")
    config = directory / f"{name}.ext"
    config.write_text("\n".join(extensions) + "\n", encoding="ascii")
    if issuer is None:
        add_extensions = [arg for entry in extensions for arg in ("-addext", entry)]
        run_openssl(
            binary, "req", *common, "-x509", "-days", str(days), "-out", cert, *add_extensions
        )
    else:
        csr = directory / f"{name}.csr"
        run_openssl(binary, "req", *common, "-out", csr)
        ca_cert, ca_key = issuer
        run_openssl(
            binary,
            "x509",
            "-req",
            "-in",
            csr,
            "-CA",
            ca_cert,
            "-CAkey",
            ca_key,
            "-CAcreateserial",
            "-days",
            str(days),
            "-extfile",
            config,
            "-out",
            cert,
        )
    return cert, key


def fingerprint(cert):
    return hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert.read_text(encoding="ascii"))).hexdigest()


def server_context(pair, intermediate=None):
    leaf, key = pair
    chain = leaf
    if intermediate is not None:
        chain = leaf.with_name(f"{leaf.stem}-chain.pem")
        chain.write_bytes(leaf.read_bytes() + intermediate.read_bytes())
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(chain, key)
    return context


def serve_once(listener, context):
    stream, _ = listener.accept()
    with stream:
        stream.settimeout(3)
        with context.wrap_socket(stream, server_side=True) as secure:
            secure.sendall(READY)


def probe(listener, workers, trust, service):
    client = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    client.minimum_version = ssl.TLSVersion.TLSv1_2
    client.hostname_checks_common_name = False
    client.verify_flags |= ssl.VERIFY_X509_STRICT
    client.load_verify_locations(cafile=trust)
    task = workers.submit(serve_once, listener, service)
    try:
        with (
            socket.create_connection(listener.getsockname(), timeout=3) as stream,
            client.wrap_socket(stream, server_hostname=HOST) as secure,
            secure.makefile("rb") as response,
        ):
            if response.readline(64) != READY:
                raise RuntimeError("service readiness response did not match")
            observed = hashlib.sha256(secure.getpeercert(binary_form=True)).hexdigest()
            expiry = ssl.cert_time_to_seconds(secure.getpeercert()["notAfter"])
    except ssl.SSLCertVerificationError:
        with suppress(ssl.SSLError):
            task.result(timeout=4)
        raise
    task.result(timeout=4)
    return observed, expiry - time()


def release_check(observed, seconds_left, expected):
    if seconds_left < BUFFER_SECONDS:
        return "insufficient lifetime"
    if observed != expected:
        return "stale certificate"
    return "pass"


def require_equal(actual, expected):
    if actual != expected:
        raise RuntimeError(f"expected {expected}, got {actual}")


def exercise(binary, directory):
    ca = ("keyUsage=critical,keyCertSign,cRLSign", "subjectKeyIdentifier=hash")
    root_ext = ("basicConstraints=critical,CA:TRUE,pathlen:1", *ca)
    root, _ = issuer = issue(binary, directory, "toolbox-root", 180, root_ext)
    other_root, _ = issue(binary, directory, "other-root", 180, root_ext)
    intermediate, _ = ca_pair = issue(
        binary,
        directory,
        "toolbox-intermediate",
        150,
        ("basicConstraints=critical,CA:TRUE,pathlen:0", "authorityKeyIdentifier=keyid,issuer", *ca),
        issuer,
    )

    def leaf(name, days, dns=HOST, purpose="serverAuth"):
        return issue(
            binary,
            directory,
            name,
            days,
            (
                "basicConstraints=critical,CA:FALSE",
                "keyUsage=critical,digitalSignature",
                "subjectKeyIdentifier=hash",
                "authorityKeyIdentifier=keyid,issuer",
                f"subjectAltName=DNS:{dns}",
                f"extendedKeyUsage={purpose}",
            ),
            ca_pair,
        )

    old = leaf("current", 60)
    candidate = leaf("candidate", 90)
    short = leaf("short", 30)
    wrong_name = leaf("wrong-name", 90, dns="other.example.test")
    wrong_purpose = leaf("client-only", 90, purpose="clientAuth")

    with socket.create_server(("127.0.0.1", 0)) as listener, ThreadPoolExecutor(1) as workers:
        listener.settimeout(3)

        def check(service, trust=root):
            return probe(listener, workers, trust, service)

        expected = fingerprint(candidate[0])
        before, remaining = check(server_context(old, intermediate))
        require_equal(before, fingerprint(old[0]))
        require_equal(release_check(before, remaining, expected), "stale certificate")

        # The same listener now serves a fresh context loaded from the candidate files.
        after, remaining = check(server_context(candidate, intermediate))
        require_equal(release_check(after, remaining, expected), "pass")

        observed, remaining = check(server_context(short, intermediate))
        require_equal(
            release_check(observed, remaining, fingerprint(short[0])), "insufficient lifetime"
        )

        rejected = []
        for label, context, trust, code in (
            ("missing intermediate", server_context(candidate), root, 20),
            ("untrusted issuer", server_context(candidate, intermediate), other_root, 20),
            ("wrong DNS SAN", server_context(wrong_name, intermediate), root, 62),
            ("client-only purpose", server_context(wrong_purpose, intermediate), root, 26),
        ):
            try:
                check(context, trust)
            except ssl.SSLCertVerificationError as error:
                require_equal(error.verify_code, code)
                rejected.append(label)
            else:
                raise RuntimeError(f"expected TLS verification to reject {label}")

    return {
        "before_rotation": "stale certificate",
        "after_rotation": "pass",
        "short_certificate": "insufficient lifetime",
        "tls_rejections": rejected,
        "previous_fingerprint": before,
        "expected_fingerprint": expected,
        "served_fingerprint": after,
    }


if __name__ == "__main__":
    openssl = shutil.which("openssl")
    if openssl is None:
        raise SystemExit("OpenSSL is required")
    with TemporaryDirectory(prefix="security-toolbox-tls-") as temporary:
        print(json.dumps(exercise(openssl, Path(temporary)), indent=2))
