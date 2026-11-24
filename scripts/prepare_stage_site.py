#!/usr/bin/env python3
"""Add ``X-Robots-Tag: noindex`` for a stage preview.

The hand-written ``site/index.html`` is left unchanged. Production deploys do
not run this script. Custom-domain Previews do not get Cloudflare's automatic
noindex header, so the header has to come from ``_headers`` in the assets
directory. The committed ``site/_headers`` already matches every path, so the
rule is merged into that block rather than appended as a second one.
``robots.txt`` must not block crawling, or crawlers never see the header: this
script does not write one, and it removes an untracked leftover.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

NOINDEX_BLOCK = "/*\n  X-Robots-Tag: noindex\n"


def merge_headers(existing: str) -> str:
    """Add the noindex rule to the ``/*`` block, or append one when absent."""
    if "X-Robots-Tag: noindex" in existing:
        return existing if existing.endswith("\n") else existing + "\n"
    lines = existing.splitlines()
    for index, line in enumerate(lines):
        if line.strip() != "/*":
            continue
        # Keep the rule inside the block that already matches every path, so the
        # file has one set of rules for the whole site rather than two.
        end = index + 1
        while end < len(lines) and lines[end].strip() and lines[end][:1].isspace():
            end += 1
        lines.insert(end, "  X-Robots-Tag: noindex")
        return "\n".join(lines) + "\n"
    text = existing
    if text and not text.endswith("\n"):
        text += "\n"
    return text + NOINDEX_BLOCK


def is_tracked(path: Path) -> bool:
    """Whether ``path`` is in the Git index. Untracked or no repo: False."""
    git = shutil.which("git")
    if git is None:
        return False
    resolved = path.resolve()
    try:
        top = subprocess.run(  # noqa: S603
            [git, "-C", str(resolved.parent), "rev-parse", "--show-toplevel"],
            check=False,
            capture_output=True,
            text=True,
        )
        if top.returncode != 0:
            return False
        root = Path(top.stdout.strip())
        relative = resolved.relative_to(root)
        listed = subprocess.run(  # noqa: S603
            [git, "-C", str(root), "ls-files", "--error-unmatch", "--", str(relative)],
            check=False,
            capture_output=True,
            text=True,
        )
    except (OSError, ValueError):
        return False
    return listed.returncode == 0


def prepare(site: Path) -> int:
    index = site / "index.html"
    if not index.is_file():
        print(f"missing {index}", file=sys.stderr)
        return 1
    headers = site / "_headers"
    # Merge whenever the file exists, tracked or not: overwriting it would drop the
    # security headers this site ships with, and merging is idempotent anyway.
    if headers.is_file():
        headers.write_text(merge_headers(headers.read_text(encoding="utf-8")), encoding="utf-8")
        print(f"merged noindex into {headers}")
    else:
        headers.write_text(NOINDEX_BLOCK, encoding="utf-8")
        print(f"wrote {headers}")
    robots = site / "robots.txt"
    if robots.is_file() and not is_tracked(robots):
        robots.unlink()
        print(f"removed untracked {robots}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument(
        "site",
        nargs="?",
        default=Path("site"),
        type=Path,
        help="site directory that wrangler.json serves (default: site)",
    )
    args = parser.parse_args(argv)
    return prepare(args.site)


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
