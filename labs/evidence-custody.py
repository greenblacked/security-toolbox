"""Check the integrity of a synthetic evidence copy against a known checksum."""

import argparse
import hashlib
import hmac
import re
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("expected_checksum", type=Path)
    args = parser.parse_args()
    try:
        expected = args.expected_checksum.read_text(encoding="ascii").strip()
        if not re.fullmatch(r"[a-f0-9]{64}", expected):
            raise ValueError("expected one lowercase SHA-256 digest")
        digest = hashlib.sha256()
        with args.evidence.open("rb") as stream:
            for chunk in iter(lambda: stream.read(65536), b""):
                digest.update(chunk)
    except (OSError, ValueError) as error:
        print(f"Evidence input error: {error}", file=sys.stderr)
        return 2
    actual = digest.hexdigest()
    if not hmac.compare_digest(actual, expected):
        print(f"FAIL SHA-256 mismatch: {actual}", file=sys.stderr)
        return 1
    print(f"PASS SHA-256: {actual}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
