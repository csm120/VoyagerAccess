"""stage-public.ps1 refuses while published files have uncommitted changes.

Fable review helper L9.3, approved by Casey 2026-11-10: the public copy is
made from HEAD (git archive), so an edit not yet committed under a published
path was silently left out of what would be published. The script now stops
first and names the files. This runs the script's own check lines (read out
of the script, from "$dirty =" through its refusal) in a scratch git
repository; the rest of the script (clone, archive, commit) is not run.

What this still passes on: the check's own git call. It says nothing about
the public repository or the push, which stay manual.
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from tests.test_stage_public_tree import PWSH, published_paths, script_text

GIT = shutil.which("git")


def dirty_check_code():
    m = re.search(r"^\$dirty = .*?^if \(\$dirty\)[^\n]*", script_text(), re.M | re.S)
    return m.group(0) if m else None


def git(repo, *args):
    subprocess.run([GIT, "-C", str(repo), *args], check=True, capture_output=True, text=True)


@unittest.skipIf(PWSH is None, "PowerShell 7 not installed")
@unittest.skipIf(GIT is None, "git not installed")
class DirtyTreeTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(dirty_check_code(), "stage-public.ps1 has no uncommitted-changes check")
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "Test")
        git(self.repo, "config", "core.autocrlf", "false")
        (self.repo / "mod").mkdir()
        (self.repo / "mod" / "main.lua").write_text("return 1\n", encoding="utf-8")
        (self.repo / "README.md").write_text("readme\n", encoding="utf-8")
        (self.repo / "notes.md").write_text("private notes\n", encoding="utf-8")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "start")

    def tearDown(self):
        self.tmp.cleanup()

    def run_check(self):
        paths = ", ".join("'" + p + "'" for p in published_paths())
        code = ("$ErrorActionPreference = 'Stop'\nSet-Location $env:VA_REPO\n"
                f"$paths = @({paths})\n" + dirty_check_code())
        with tempfile.NamedTemporaryFile("w", suffix=".ps1", delete=False, encoding="utf-8") as f:
            f.write(code)
        try:
            return subprocess.run([PWSH, "-NoProfile", "-NonInteractive", "-File", f.name],
                                  capture_output=True, text=True, timeout=120,
                                  env=dict(os.environ, VA_REPO=str(self.repo)))
        finally:
            os.unlink(f.name)

    def test_an_uncommitted_edit_under_a_published_path_stops_and_is_named(self):
        (self.repo / "mod" / "main.lua").write_text("return 2\n", encoding="utf-8")
        (self.repo / "README.md").write_text("changed\n", encoding="utf-8")
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("UNCOMMITTED: mod/main.lua", result.stdout)
        self.assertIn("UNCOMMITTED: README.md", result.stdout)
        self.assertIn("uncommitted changes", result.stdout + result.stderr)

    def test_a_staged_but_uncommitted_edit_also_stops(self):
        (self.repo / "mod" / "main.lua").write_text("return 3\n", encoding="utf-8")
        git(self.repo, "add", "mod/main.lua")
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_a_clean_tree_stages(self):
        # Negative twin: nothing uncommitted, the check lets the script go on.
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("UNCOMMITTED", result.stdout)

    def test_unpublished_and_untracked_files_do_not_stop_it(self):
        # git archive takes neither, so neither can be left out by mistake.
        (self.repo / "notes.md").write_text("edited\n", encoding="utf-8")
        (self.repo / "mod" / "scratch.lua").write_text("x\n", encoding="utf-8")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_the_check_runs_before_anything_is_cloned_or_deleted(self):
        text = script_text()
        at = text.find("$dirty = ")
        self.assertGreaterEqual(at, 0)
        self.assertLess(at, text.find("git clone"))
        self.assertLess(at, text.find("Remove-Item"))


if __name__ == "__main__":
    unittest.main()
