#!/usr/bin/env python3
"""Build MkDocs and add its output to the CI copy of the Worker asset directory."""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    assets = root / "site"

    with tempfile.TemporaryDirectory() as temporary:
        output = Path(temporary)
        subprocess.run(  # noqa: S603
            [sys.executable, "-m", "mkdocs", "build", "--strict", "--site-dir", str(output)],
            cwd=root,
            check=True,
        )
        for path in ("kubernetes", "gcp", "terraform", "github", "secrets", "contributing", "ci"):
            if not (output / path / "index.html").is_file():
                raise SystemExit(f"Missing generated guide: {path}/index.html")

        entries = [entry for entry in output.iterdir() if entry.name != "index.html"]
        for entry in entries:
            if (assets / entry.name).exists():
                raise SystemExit(f"Generated docs collide with a Worker asset: {entry.name}")
        for entry in entries:
            target = assets / entry.name
            if entry.is_dir():
                shutil.copytree(entry, target)
            else:
                shutil.copy2(entry, target)


if __name__ == "__main__":
    main()
