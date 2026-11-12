"""stage-public.ps1's private-reference check catches private paths in every form.

Fable review, 2026-11-10 (helper findings 6 and 9.1; Casey's answer the same
day): the check matched Casey's user folder only with single backslashes,
and no cloud-drive or business workspace path at all. This file is
published, so it builds those words from parts and never spells them
(stage-public.ps1 would refuse it). The script's own pattern is read from
it and run through PowerShell's Select-String, as the script does, so .NET's
regex engine and its case rules are what is tested. The script itself is not
run (it clones and stages the public repository).
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "tools" / "stage-public.ps1"
PWSH = shutil.which("pwsh") or next(
    (p for p in [os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "PowerShell", "7", "pwsh.exe")]
     if os.path.exists(p)), None)

CHECK = r"""
$pattern = [IO.File]::ReadAllText($env:VA_PATTERN_FILE)
$hits = Select-String -Path (Get-ChildItem $env:VA_SAMPLES -File).FullName -Pattern $pattern
$hits | ForEach-Object { $_.Filename }
"""

BS = chr(92)
DRIVE = "One" + "Drive"
WORK = "W" + "FH"
ME = "csm" + "12"
CAUGHT = {
    "cloud.txt": "C:" + BS + DRIVE + BS + "Documents" + BS + "x.docx",
    "work_forward.txt": "see C:/Data/Downloads/" + WORK + "/business-facts.md",
    "work_backslash.txt": "Downloads" + BS + WORK + BS + "review",
    "users_single.txt": "C:" + BS + "Users" + BS + ME + BS + "x",
    "users_forward.txt": "C:/Users/" + ME + "/.claude",
    "users_doubled.txt": "C:" + BS * 2 + "Users" + BS * 2 + ME + BS * 2 + "x",
}
ALLOWED = {
    "fake_user.txt": "C:" + BS + "Users" + BS + "Player" + BS + "AppData",
    "wfh_words.txt": "the WFH session's reliability review",
    "wfh_signing.txt": 'ACCOUNT = "wfhsigning"; SignTool=wfh; /Swfh=$signTool',
}


def pattern():
    text = SCRIPT.read_text(encoding="utf-8")
    m = re.search(r"^\$private = '([^']*)'", text, re.M)
    return m.group(1) if m else None


@unittest.skipIf(PWSH is None, "PowerShell 7 not installed")
class LeakPatternTests(unittest.TestCase):
    def hits(self, samples):
        p = pattern()
        self.assertIsNotNone(p, "stage-public.ps1 has no $private = '...' line")
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "samples").mkdir()
            for name, text in samples.items():
                (d / "samples" / name).write_text(text, encoding="utf-8")
            (d / "pattern.txt").write_text(p, encoding="utf-8")
            env = dict(os.environ, VA_PATTERN_FILE=str(d / "pattern.txt"), VA_SAMPLES=str(d / "samples"))
            out = subprocess.run([PWSH, "-NoProfile", "-NonInteractive", "-Command", CHECK],
                                 capture_output=True, text=True, env=env, timeout=60)
            self.assertEqual(out.returncode, 0, out.stderr)
            return set(out.stdout.split())

    def test_private_paths_are_caught(self):
        self.assertEqual(self.hits(CAUGHT), set(CAUGHT))

    def test_ordinary_text_is_not_caught(self):
        # Negative twin: what the public tree has today must still pass.
        self.assertEqual(self.hits(ALLOWED), set())

    def test_old_private_file_names_still_caught(self):
        self.assertEqual(self.hits({"notes.txt": "see implementation" + "-notes.md"}), {"notes.txt"})


if __name__ == "__main__":
    unittest.main()
