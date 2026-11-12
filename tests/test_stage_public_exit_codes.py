"""stage-public.ps1 stops when git or tar fails.

Fable review, 2026-11-10 (helper low 9.2): git clone, git archive, tar,
git add and git commit are native commands, and $ErrorActionPreference =
'Stop' does not cover them, so a failed commit still printed "staged N
files". The script is not run here (it clones and stages the public
repository); this checks that each such line is followed by a
$LASTEXITCODE throw.
"""
import re
import unittest
from pathlib import Path

LINES = (Path(__file__).resolve().parent.parent / "tools" / "stage-public.ps1").read_text(encoding="utf-8").splitlines()
NATIVE = re.compile(r"^\s*(git (clone|archive|add|-c .* commit)|tar )")


class StagePublicExitCodeTests(unittest.TestCase):
    def test_each_native_step_is_checked(self):
        found = 0
        for i, line in enumerate(LINES):
            if NATIVE.match(line):
                found += 1
                self.assertRegex(LINES[i + 1], r"if \(\$LASTEXITCODE\) \{ (Pop-Location; )?throw ", f"line {i + 1}: {line.strip()}")
        self.assertEqual(found, 5)


if __name__ == "__main__":
    unittest.main()
