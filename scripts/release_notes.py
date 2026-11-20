#!/usr/bin/env python3
"""Read release notes and enforce monotonic tags."""
import re
import subprocess
import sys
from pathlib import Path

VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
HEADING = re.compile(r"^## \[([^]]+)\](?:\s*-\s*\d{4}-\d{2}-\d{2})?\s*$", re.M)


def sections(text):
    matches = list(HEADING.finditer(text))
    result = []
    for i, match in enumerate(matches):
        version = match.group(1)
        if VERSION.fullmatch(version):
            end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
            body = re.split(r"^\[[^]]+\]:\s", text[match.end():end], maxsplit=1, flags=re.M)[0].strip()
            result.append((version, body))
    return result


def key(version):
    match = VERSION.fullmatch(version)
    if not match:
        raise ValueError("version must be X.Y.Z without leading zeroes")
    return tuple(map(int, match.groups()))


def latest(text):
    entries = sections(text)
    if not entries or len({v for v, _ in entries}) != len(entries):
        raise ValueError("missing or duplicate release sections")
    version, body = entries[0]
    if not body or any(key(v) >= key(version) for v, _ in entries[1:]):
        raise ValueError("latest release must have notes and precede older versions")
    return version


def notes(text, version):
    if latest(text) != version:
        raise ValueError("tag must match latest changelog version")
    return sections(text)[0][1]


def check_tags(version, tags):
    target = key(version)
    for tag in tags:
        if tag.startswith("v") and VERSION.fullmatch(tag[1:]) and key(tag[1:]) > target:
            raise ValueError("a newer release tag already exists: " + tag)


def main():
    try:
        command = sys.argv[1]
        text = Path("CHANGELOG.md").read_text(encoding="utf-8")
        version = latest(text)
        if command == "latest":
            print(version)
        elif command == "notes":
            print(notes(text, sys.argv[2].removeprefix("v")))
        elif command == "check-tags":
            if sys.argv[2] != version:
                raise ValueError("version is not latest")
            tags = subprocess.run(["git", "tag", "--list", "v*"], check=True,
                                  capture_output=True, text=True).stdout.splitlines()
            check_tags(version, tags)
        else:
            raise ValueError("unknown command")
    except (ValueError, IndexError, OSError, subprocess.CalledProcessError) as exc:
        print(f"::error::{exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
