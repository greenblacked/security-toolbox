#!/usr/bin/env python3
"""Write a noindex robots.txt for the stage Preview.

The hand-written ``site/index.html`` is left unchanged. Production deploys do
not run this script, so production keeps whatever robots.txt is in the tree
(none, unless one is added later). wrangler preview has no ``--noindex`` flag;
this is the equivalent of the site-build ``--noindex`` used in greenblacked/AI.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROBOTS = "User-agent: *\nDisallow: /\n"


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
    site: Path = args.site
    index = site / "index.html"
    if not index.is_file():
        print(f"missing {index}", file=sys.stderr)
        return 1
    (site / "robots.txt").write_text(ROBOTS, encoding="utf-8")
    print(f"wrote {site / 'robots.txt'} (noindex)")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
