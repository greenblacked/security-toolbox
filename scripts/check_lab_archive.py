"""Check the lab kit's member paths and optionally exercise a local build."""

import argparse
import json
import os
import subprocess
import sys
import tarfile
from pathlib import Path, PurePosixPath
from tempfile import TemporaryDirectory

REQUIRED_FILES = {"LICENSE", "labs/tls-rotation.py", "labs/service-restore.py"}


def inspect(archive):
    files = set()
    for member in archive:
        name = PurePosixPath(member.name)
        if (
            not member.isfile()
            or name.is_absolute()
            or ".." in name.parts
            or "\\" in member.name
            or name.as_posix() != member.name
            or member.name in files
        ):
            raise ValueError(f"unexpected archive member {member.name!r}")
        files.add(member.name)
    missing = REQUIRED_FILES - files
    if missing:
        raise ValueError(f"missing archive files: {', '.join(sorted(missing))}")
    # Detect a regular file occupying the path of another entry's parent.
    if any(parent.as_posix() in files for name in files for parent in PurePosixPath(name).parents):
        raise ValueError("archive file occupies another member's parent path")
    print(f"Lab archive contains {len(files)} regular files")


def run_lab(root, name):
    # Run the locally built kit in a fresh directory and strip runner credentials.
    env = {
        "HOME": str(root),
        "PATH": os.environ.get("PATH", os.defpath),
        "TMPDIR": str(root),
    }
    result = subprocess.run(  # noqa: S603 - fixed interpreter and local build fixtures
        [sys.executable, "-I", str(root / "labs" / name)],
        cwd=root,
        env=env,
        stdout=subprocess.PIPE,
        text=True,
        check=True,
        timeout=30,
    )
    return json.loads(result.stdout)


def exercise(archive):
    with TemporaryDirectory(prefix="security-toolbox-lab-kit-") as directory:
        root = Path(directory)
        archive.extractall(root, filter="data")
        tls = run_lab(root, "tls-rotation.py")
        if (
            tls["before_rotation"] != "stale certificate"
            or tls["after_rotation"] != "pass"
            or tls["served_fingerprint"] != tls["expected_fingerprint"]
            or tls["short_certificate"] != "insufficient lifetime"
            or set(tls["tls_rejections"])
            != {"missing intermediate", "untrusted issuer", "wrong DNS SAN", "client-only purpose"}
        ):
            raise ValueError("TLS lab did not verify rotation and rejected certificate cases")

        restore = run_lab(root, "service-restore.py")
        if (
            restore["restored_order_ids"] != [1, 2]
            or restore["missing_order_ids"] != [3]
            or restore["recovery_point_gap_seconds"] != 60
            or restore["recovery_point_target_met"] is not False
            or restore["local_restore_target_met"] is not True
        ):
            raise ValueError("restore lab did not report the expected recovery outcome")
    print("TLS rotation and service restore passed from the extracted local kit")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--exercise-local-build", action="store_true")
    args = parser.parse_args()
    try:
        with tarfile.open(args.archive, "r:gz") as archive:
            inspect(archive)
            if args.exercise_local_build:
                exercise(archive)
    except (OSError, tarfile.TarError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Lab archive check failed: {error}\n")


if __name__ == "__main__":
    main()
