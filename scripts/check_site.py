#!/usr/bin/env python3
"""Check the built site before it is deployed.

Two classes of defect ship silently otherwise: a link to a route or anchor that no
longer exists, and a page missing the head or landmark structure the shell
promises. Both are cheap to check on the rendered output, which is what deploys.

Usage: check_site.py [site-directory]
Exit codes: 0 clean, 1 at least one error.
"""

from __future__ import annotations

import argparse
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

SKIP_SCHEMES = ("mailto:", "tel:", "data:")
ASSET_TAGS = {"script", "img", "source"}


class Page(HTMLParser):
    """The parts of a page this check cares about."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.lang: str | None = None
        self.title = ""
        self.links: list[str] = []
        self.metas: list[dict[str, str]] = []
        self.canonical = ""
        self.h1 = 0
        self.ids: list[str] = []
        self.has_main = False
        self._in_title = False
        self._title_parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {name: value or "" for name, value in attrs}
        if tag == "html":
            self.lang = values.get("lang")
        elif tag == "title":
            self._in_title = True
        elif tag == "meta":
            self.metas.append(values)
        elif tag == "link":
            if values.get("rel") == "canonical":
                self.canonical = values.get("href", "")
            if values.get("href"):
                self.links.append(values["href"])
        elif tag == "h1":
            self.h1 += 1
        elif tag == "main":
            self.has_main = True
        if tag == "a" and values.get("href"):
            self.links.append(values["href"])
        elif tag in ASSET_TAGS and values.get("src"):
            self.links.append(values["src"])
        if values.get("id"):
            self.ids.append(values["id"])

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._in_title = False
            self.title = "".join(self._title_parts).strip()

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self._title_parts.append(data)


def read(page: Path) -> Page:
    parser = Page()
    parser.feed(page.read_text(encoding="utf-8"))
    parser.close()
    return parser


def meta(page: Page, key: str) -> str:
    for entry in page.metas:
        if entry.get("name") == key or entry.get("property") == key:
            return entry.get("content", "")
    return ""


def is_external(href: str) -> bool:
    return "://" in href or href.startswith(SKIP_SCHEMES)


def resolve(root: Path, page: Path, href: str) -> Path | None:
    """The file a local href points at, or None when it leaves the site."""
    if not href or is_external(href):
        return None
    path = urlsplit(href).path
    if not path:
        return None
    target = root / path.lstrip("/") if path.startswith("/") else page.parent / path
    if target.is_dir():
        return target / "index.html"
    if target.suffix:
        return target
    return target / "index.html"


def check(root: Path) -> list[str]:
    problems: list[str] = []
    pages = sorted(root.rglob("*.html"))
    if not pages:
        return [f"no HTML found under {root}"]
    parsed = {page.resolve(): read(page) for page in pages}

    for page, document in parsed.items():
        name = page.relative_to(root).as_posix()
        noindex = "noindex" in meta(document, "robots")
        if not document.lang:
            problems.append(f"{name}: <html> has no lang attribute")
        if not document.title:
            problems.append(f"{name}: missing <title>")
        if document.h1 != 1:
            problems.append(f"{name}: expected one <h1>, found {document.h1}")
        if not document.has_main:
            problems.append(f"{name}: missing <main> landmark")
        if not meta(document, "viewport"):
            problems.append(f"{name}: missing viewport meta")
        if not meta(document, "description"):
            problems.append(f"{name}: missing meta description")
        if not noindex and not meta(document, "og:url"):
            problems.append(f"{name}: missing og:url")
        if not noindex and not document.canonical:
            problems.append(f"{name}: missing canonical link")
        seen: set[str] = set()
        for value in document.ids:
            if value in seen:
                problems.append(f"{name}: duplicate id {value!r}")
            seen.add(value)

    for page, document in parsed.items():
        name = page.relative_to(root).as_posix()
        for href in document.links:
            if is_external(href):
                continue
            fragment = urlsplit(href).fragment
            target = resolve(root, page, href)
            if target is None:
                if fragment and fragment not in document.ids:
                    problems.append(f"{name}: link {href} points at a missing anchor")
                continue
            if not target.exists():
                problems.append(f"{name}: link {href} points at a missing file")
                continue
            target = target.resolve()
            if fragment and target in parsed and fragment not in parsed[target].ids:
                problems.append(f"{name}: link {href} points at a missing anchor")

    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("site", nargs="?", default="site", type=Path)
    args = parser.parse_args(argv)
    root = args.site.resolve()
    if not root.is_dir():
        print(f"missing {args.site}", file=sys.stderr)
        return 1
    problems = check(root)
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        print(f"{len(problems)} problem(s) in {args.site}")
        return 1
    print(f"{args.site} looks consistent")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
