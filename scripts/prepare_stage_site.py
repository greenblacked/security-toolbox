#!/usr/bin/env python3
"""Write a stage-only ``_headers`` file with ``X-Robots-Tag: noindex``.

The hand-written ``site/index.html`` is left unchanged. Production deploys do
not run this script. Custom-domain Previews do not get Cloudflare's automatic
noindex header, so the header has to come from ``_headers`` in the assets
directory. ``robots.txt`` must not block crawling, or crawlers never see the
header: this script does not write one, and it removes an untracked leftover.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

NOINDEX_BLOCK = "/*\n  X-Robots-Tag: noindex\n"


def merge_headers(existing: str) -> str:
    """Append the noindex rule unless that header is already present."""
    if "X-Robots-Tag: noindex" in existing:
        return existing if existing.endswith("\n") else existing + "\n"
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
    if headers.is_file() and is_tracked(headers):
        headers.write_text(merge_headers(headers.read_text(encoding="utf-8")), encoding="utf-8")
        print(f"merged noindex into tracked {headers}")
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
