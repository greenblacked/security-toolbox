#!/usr/bin/env python3
"""Local tests for the Wrangler pin, log-reader and stage-site helpers."""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from check_wrangler_pin import problems
from prepare_stage_site import ROBOTS
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
    def test_writes_robots_and_leaves_index(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        site = Path(tmp.name) / "site"
        site.mkdir()
        index = site / "index.html"
        body = "<!doctype html><title>Security Toolbox</title>\n"
        index.write_text(body, encoding="utf-8")
        self.assertEqual(prepare_main([str(site)]), 0)
        self.assertEqual((site / "robots.txt").read_text(encoding="utf-8"), ROBOTS)
        self.assertEqual(index.read_text(encoding="utf-8"), body)

    def test_missing_index(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        site = Path(tmp.name) / "site"
        site.mkdir()
        self.assertEqual(prepare_main([str(site)]), 1)


if __name__ == "__main__":
    os.chdir(Path(__file__).resolve().parent)
    raise SystemExit(unittest.main())
