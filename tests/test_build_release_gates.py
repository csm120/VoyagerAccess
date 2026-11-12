"""installer/build.ps1 runs the tests and the translation check for a release.

Fable review, 2026-11-10 (helper low 12), Casey's answer the same day: a
release could be built and signed with the suite failing or the tables
incomplete. build.ps1 cannot be run here (it signs and builds), so this
checks its text: inside the three-part (release) version block, both
commands run, each is followed by a $LASTEXITCODE throw, and both come
before anything is built or signed.
"""
import re
import unittest
from pathlib import Path

BUILD = (Path(__file__).resolve().parent.parent / "installer" / "build.ps1").read_text(encoding="utf-8")


def release_block():
    m = re.search(r"if \(\(\$version -split '\\\.'\)\.Count -eq 3\) \{(.*?)\n\}", BUILD, re.S)
    return m.group(1) if m else ""


class ReleaseGateTests(unittest.TestCase):
    def test_release_block_runs_both_checks(self):
        block = release_block()
        self.assertIn("-m unittest discover -s tests", block)
        self.assertIn("tools\\check_translations.py", block)

    def test_each_check_stops_the_build(self):
        block = release_block()
        for cmd in ("-m unittest discover", "check_translations.py"):
            after = block[block.find(cmd):]
            self.assertRegex(after.split("\n", 2)[1], r"if \(\$LASTEXITCODE\) \{ throw ")

    def test_release_refuses_when_lupa_is_missing(self):
        # Pre-merge review, 2026-11-10 (low 8.3): every Lua test skips
        # without lupa, so the unittest gate passed with the mod untested.
        block = release_block()
        probe = block.find('py -3.11 -c "import lupa"')
        self.assertGreaterEqual(probe, 0, "the release block does not check for lupa")
        self.assertRegex(block[probe:].split("\n", 2)[1], r"if \(\$LASTEXITCODE\) \{ throw ")
        self.assertLess(probe, block.find("-m unittest discover"))

    def test_test_builds_do_not_need_lupa(self):
        # Negative twin: the check sits only in the release block, so a
        # four-part test build is not stopped by it.
        outside = BUILD.replace(release_block(), "")
        self.assertNotIn("import lupa", outside)

    def test_checks_come_before_signing_and_building(self):
        self.assertLess(BUILD.find("check_translations.py"), BUILD.find("codesign.py --can-sign"))
        self.assertLess(BUILD.find("-m unittest discover"), BUILD.find("build_native.ps1"))


if __name__ == "__main__":
    unittest.main()
