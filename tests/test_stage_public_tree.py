"""The files stage-public.ps1 publishes pass its own content checks.

Pre-merge review, 2026-11-10 (finding M1): a comment in voyager and a test
sample in tests named a private file, so the next staging of the public copy
would have stopped with "references to private files remain". This runs the
script's own swap and check code (the lines from its $swaps table to its last
content refusal, read out of the script, not copied) over a copy of the
tracked files under the script's $paths, so a new private reference, a game
data extraction call, a word from the secret-word list or the other mod's name
in any published file fails here first. The rest of the script (clone,
archive, commit) is not run. Since the 0.4.3 release (2026-11-11), when this
file's own docstring was refused by staging, the run reaches every refusal,
not just the private-file one.

What this still passes on: a file the script publishes that git does not
track yet (the script archives HEAD, this copies tracked files from the
working tree), which only the real staging run checks.
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "tools" / "stage-public.ps1"
PWSH = shutil.which("pwsh") or next(
    (p for p in [os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "PowerShell", "7", "pwsh.exe")]
     if os.path.exists(p)), None)


def script_text():
    return SCRIPT.read_text(encoding="utf-8")


def published_paths():
    """The script's $paths list (it may run over two lines)."""
    m = re.search(r"^\$paths = @\((.*?)\)", script_text(), re.M | re.S)
    return re.findall(r"'([^']+)'", m.group(1)) if m else []


def check_code():
    """The script's own lines from the $swaps table through its last content
    refusal (private files, extraction code, the secret words, the other mod)."""
    text = script_text()
    start = text.find("$swaps = [ordered]@{")
    m = re.search(r"^if \(\$other\).*$", text[start:], re.M) if start >= 0 else None
    return text[start:start + m.end()] if m else None


def run_check(folder):
    code = "$ErrorActionPreference = 'Stop'\n$out = $env:VA_OUT\n" + check_code()
    with tempfile.NamedTemporaryFile("w", suffix=".ps1", delete=False, encoding="utf-8") as f:
        f.write(code)
    try:
        return subprocess.run([PWSH, "-NoProfile", "-NonInteractive", "-File", f.name],
                              capture_output=True, text=True, timeout=120,
                              env=dict(os.environ, VA_OUT=str(folder)))
    finally:
        os.unlink(f.name)


@unittest.skipIf(PWSH is None, "PowerShell 7 not installed")
@unittest.skipIf(shutil.which("git") is None or not (ROOT / ".git").exists(), "needs the git working copy")
class PublishedTreeTests(unittest.TestCase):
    def test_script_parts_found(self):
        self.assertIn("voyager", published_paths())
        self.assertIn("tests", published_paths())
        self.assertIsNotNone(check_code())
        self.assertIn("$private", check_code())
        # 0.4.3 release, 2026-11-11: staging refused a word in this file's own
        # docstring while the suite was green, because the check stopped at
        # $private. The run now reaches every content refusal.
        for name in ("$extract", "$secret", "$other"):
            self.assertIn("if (%s)" % name, check_code())

    def test_published_files_pass_the_check(self):
        files = subprocess.run(["git", "ls-files", "-z", "--"] + published_paths(), cwd=ROOT,
                               capture_output=True, text=True, check=True).stdout.split("\0")
        files = [f for f in files if f]
        # The loop below must have something to check: a silent empty list passes.
        self.assertGreater(len(files), 50)
        with tempfile.TemporaryDirectory() as d:
            for rel in files:
                src = ROOT / rel
                if src.is_file():
                    dest = Path(d) / rel
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src, dest)
            out = run_check(d)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)

    def test_check_refuses_a_private_reference(self):
        # Negative twin: the same code run over one bad file must fail, or a
        # pass above proves nothing.
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "voyager").mkdir()
            (Path(d) / "voyager" / "bad.py").write_text(
                "# see " + "implementation" + "-notes.md\n", encoding="utf-8")
            out = run_check(d)
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("LEFT: bad.py:1", out.stdout)

    def test_check_refuses_a_secret_word(self):
        # Negative twin for the secret-word refusal. The word is assembled so
        # this published file never spells it.
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "tests").mkdir()
            (Path(d) / "tests" / "bad.py").write_text(
                "# the " + "de" + "cryption step\n", encoding="utf-8")
            out = run_check(d)
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("PRIVATE: bad.py:1", out.stdout)


if __name__ == "__main__":
    unittest.main()
