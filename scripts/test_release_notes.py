import unittest

from release_notes import check_tags, latest, notes

LOG = """# Changelog

## [Unreleased]

## [0.1.0] - 2026-11-20

### Added

- First release.
"""


class ReleaseNotesTests(unittest.TestCase):
    def test_initial_release_and_notes(self):
        self.assertEqual(latest(LOG), "0.1.0")
        self.assertEqual(notes(LOG, "0.1.0"), "### Added\n\n- First release.")

    def test_same_tag_allowed_for_retry_but_newer_rejected(self):
        check_tags("0.1.0", ["v0.1.0"])
        with self.assertRaises(ValueError):
            check_tags("0.1.0", ["v0.2.0"])

    def test_empty_duplicate_or_out_of_order_refused(self):
        for text in (
            "## [1.0.0]\n",
            LOG + "\n## [0.1.0]\n- duplicate\n",
            LOG + "\n## [1.0.0]\n- newer\n",
        ):
            with self.subTest(text=text), self.assertRaises(ValueError):
                latest(text)

    def test_wrong_version_and_invalid_semver_rejected(self):
        with self.assertRaises(ValueError):
            notes(LOG, "0.0.9")
        with self.assertRaises(ValueError):
            check_tags("01.0.0", [])


if __name__ == "__main__":
    unittest.main()
