#!/usr/bin/env python3
"""Local tests for the Wrangler pin, log-reader and stage-site helpers."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from check_wrangler_pin import problems
from prepare_stage_site import NOINDEX_BLOCK, merge_headers
from prepare_stage_site import main as prepare_main
from read_wrangler_deploy import parse_active, parse_deploy, parse_preview

VERSION = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
CUSTOM = "security.szolotov.com (custom domain) [previews: enabled]"


class CheckWranglerPin(unittest.TestCase):
    def _tree(self, package: dict, lock: dict) -> Path:
        root = Path(self._tmp.name)
        deploy = root / "deploy"
        deploy.mkdir()
        (deploy / "package.json").write_text(json.dumps(package), encoding="utf-8")
        (deploy / "package-lock.json").write_text(json.dumps(lock), encoding="utf-8")
        return root

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)

    def test_environment_custom_domains(self):
        for host in ("dev.security.szolotov.com", "stage.security.szolotov.com"):
            log = json.dumps(
                {
                    "type": "deploy",
                    "targets": [
                        "https://security-dev.account.workers.dev",
                        f"{host} (custom domain)",
                    ],
                }
            )
            self.assertEqual(parse_deploy(log)[2], f"https://{host}")
        log = json.dumps(
            {
                "type": "deploy",
                "targets": [
                    "https://security-dev.account.workers.dev",
                    "dev.security.szolotov.com.evil.com (custom domain)",
                ],
            }
        )
        self.assertEqual(parse_deploy(log)[2], "")

    def test_match(self) -> None:
        root = self._tree(
            {"dependencies": {"wrangler": "4.149.0"}},
            {
                "packages": {
                    "node_modules/wrangler": {
                        "version": "4.149.0",
                        "integrity": "sha512-" + "a" * 88,
                    }
                }
            },
        )
        self.assertEqual(problems(root, "4.149.0"), [])

    def test_mismatch_and_missing_integrity(self) -> None:
        root = self._tree(
            {"dependencies": {"wrangler": "4.0.0"}},
            {"packages": {"node_modules/wrangler": {"version": "4.1.0"}}},
        )
        found = problems(root, "4.149.0")
        self.assertTrue(any("package.json" in item for item in found))
        self.assertTrue(any("package-lock.json" in item for item in found))
        self.assertTrue(any("integrity" in item for item in found))

    def test_missing_files(self) -> None:
        self.assertEqual(
            problems(Path(self._tmp.name), "4.149.0"),
            ["missing deploy/package.json or deploy/package-lock.json"],
        )


class ReadWranglerDeploy(unittest.TestCase):
    def test_deploy_urls(self) -> None:
        log = "\n".join(
            [
                json.dumps(
                    {
                        "type": "deploy",
                        "version_id": VERSION,
                        "targets": [
                            "https://security.account.workers.dev",
                            CUSTOM,
                        ],
                    }
                )
            ]
        )
        url, version_id, custom = parse_deploy(log)
        self.assertEqual(url, "https://security.account.workers.dev")
        self.assertEqual(version_id, VERSION)
        self.assertEqual(custom, "https://security.szolotov.com")

    def test_deploy_rejects_missing_workers_dev(self) -> None:
        log = json.dumps({"type": "deploy", "targets": [CUSTOM]})
        with self.assertRaises(SystemExit):
            parse_deploy(log)

    def test_preview_stage_url(self) -> None:
        log = json.dumps(
            {
                "type": "preview",
                "preview_urls": [
                    "https://stage-security.account.workers.dev",
                    "https://stage.security.szolotov.com",
                ],
            }
        )
        url, custom = parse_preview(log)
        self.assertEqual(url, "https://stage-security.account.workers.dev")
        self.assertEqual(custom, "https://stage.security.szolotov.com")

    def test_preview_rejects_empty(self) -> None:
        with self.assertRaises(SystemExit):
            parse_preview("")

    def test_active_full_traffic(self) -> None:
        status = json.dumps({"versions": [{"version_id": VERSION, "percentage": 100}]})
        self.assertEqual(parse_active(status), VERSION)

    def test_active_rejects_split(self) -> None:
        status = json.dumps(
            {
                "versions": [
                    {"version_id": VERSION, "percentage": 50},
                    {
                        "version_id": "11111111-2222-3333-4444-555555555555",
                        "percentage": 50,
                    },
                ]
            }
        )
        with self.assertRaises(SystemExit):
            parse_active(status)


class PrepareStageSite(unittest.TestCase):
    def _site(self) -> tuple[Path, Path, str]:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        site = Path(tmp.name) / "site"
        site.mkdir()
        index = site / "index.html"
        body = "<!doctype html><title>Security Toolbox</title>\n"
        index.write_text(body, encoding="utf-8")
        return site, index, body

    def test_writes_headers_and_leaves_index(self) -> None:
        site, index, body = self._site()
        self.assertEqual(prepare_main([str(site)]), 0)
        self.assertEqual((site / "_headers").read_text(encoding="utf-8"), NOINDEX_BLOCK)
        self.assertFalse((site / "robots.txt").exists())
        self.assertEqual(index.read_text(encoding="utf-8"), body)

    def test_removes_untracked_blocking_robots(self) -> None:
        site, index, body = self._site()
        (site / "robots.txt").write_text("User-agent: *\nDisallow: /\n", encoding="utf-8")
        self.assertEqual(prepare_main([str(site)]), 0)
        self.assertFalse((site / "robots.txt").exists())
        self.assertEqual((site / "_headers").read_text(encoding="utf-8"), NOINDEX_BLOCK)
        self.assertEqual(index.read_text(encoding="utf-8"), body)

    def test_merge_headers_appends_and_is_idempotent(self) -> None:
        existing = "/assets/*\n  Cache-Control: public, max-age=60\n"
        merged = merge_headers(existing)
        self.assertIn("Cache-Control: public, max-age=60", merged)
        self.assertTrue(merged.endswith(NOINDEX_BLOCK))
        self.assertEqual(merge_headers(merged), merged)

    def test_merge_headers_extends_the_catch_all_block(self) -> None:
        existing = "/*\n  X-Frame-Options: DENY\n\n/fonts/*\n  Cache-Control: public\n"
        merged = merge_headers(existing)
        self.assertIn("/*\n  X-Frame-Options: DENY\n  X-Robots-Tag: noindex\n", merged)
        self.assertEqual([line for line in merged.splitlines() if line.strip() == "/*"], ["/*"])
        self.assertEqual(merge_headers(merged), merged)

    def test_untracked_headers_are_merged_not_replaced(self) -> None:
        # A preview must keep the security headers it ships with. Only a missing
        # file may be created from scratch.
        site, _, _ = self._site()
        existing = "/*\n  X-Frame-Options: DENY\n"
        (site / "_headers").write_text(existing, encoding="utf-8")
        self.assertEqual(prepare_main([str(site)]), 0)
        merged = (site / "_headers").read_text(encoding="utf-8")
        self.assertIn("X-Frame-Options: DENY", merged)
        self.assertIn("X-Robots-Tag: noindex", merged)

    def test_merges_tracked_headers(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        site = root / "site"
        site.mkdir()
        index = site / "index.html"
        body = "<!doctype html><title>Security Toolbox</title>\n"
        index.write_text(body, encoding="utf-8")
        existing = "/assets/*\n  Cache-Control: public, max-age=60\n"
        (site / "_headers").write_text(existing, encoding="utf-8")
        self._git(root, ["init"])
        self._git(root, ["add", "site/_headers"])
        self._git(
            root,
            [
                "-c",
                "user.name=greenblacked",
                "-c",
                "user.email=zolotov.98@gmail.com",
                "commit",
                "-m",
                "headers",
            ],
        )
        self.assertEqual(prepare_main([str(site)]), 0)
        self.assertEqual((site / "_headers").read_text(encoding="utf-8"), merge_headers(existing))
        self.assertEqual(index.read_text(encoding="utf-8"), body)

    def _git(self, root: Path, args: list[str]) -> None:
        git = shutil.which("git")
        if git is None:
            self.fail("git is not on PATH")
        subprocess.run([git, "-C", str(root), *args], check=True, capture_output=True)  # noqa: S603

    def test_missing_index(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        site = Path(tmp.name) / "site"
        site.mkdir()
        self.assertEqual(prepare_main([str(site)]), 1)


if __name__ == "__main__":
    os.chdir(Path(__file__).resolve().parent)
    raise SystemExit(unittest.main())
