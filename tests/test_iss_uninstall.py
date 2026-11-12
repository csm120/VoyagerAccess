"""VoyagerAccess.iss: the mod comes out only after the player confirms.

Pre-merge review, 2026-11-10 (H1): Inno Setup calls InitializeUninstall
before its own "Are you sure you want to completely remove" question
(Setup.Uninstall.pas runs InitializeUninstall, then msgConfirmUninstall,
then CurUninstallStepChanged(usAppMutexCheck) and, once the progress form
is up, CurUninstallStepChanged(usUninstall)). The helper kill and
--uninstall-mod sat in InitializeUninstall, so answering No left the mod
half removed. Abort is documented as stopping the uninstall from
CurUninstallStepChanged(usUninstall).

The uninstaller itself can only be run in the VM, so this checks the
script's text. It still passes on a script Inno Setup would not compile
(compile it) and says nothing about what the player hears.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from voyager import app  # noqa: E402

ISS = (ROOT / "installer" / "VoyagerAccess.iss").read_text(encoding="utf-8")


def body(header):
    """The text of one [Code] function or procedure, header to its end."""
    m = re.search(r"^(function|procedure) " + re.escape(header) + r"\b.*?^end;", ISS, re.M | re.S)
    return m.group(0) if m else ""


class UninstallOrderTests(unittest.TestCase):
    def test_nothing_is_removed_before_the_question(self):
        early = body("InitializeUninstall")
        for action in ("--uninstall-mod", "taskkill", "RegDeleteValue"):
            self.assertNotIn(action, early)

    def test_removal_runs_at_the_uninstall_step_and_can_stop_it(self):
        step = body("CurUninstallStepChanged")
        self.assertIn("usUninstall", step)
        self.assertIn("--uninstall-mod", step)
        self.assertIn("Abort", step)

    def test_run_once_entry_is_kept_when_uninstall_stops(self):
        # Review L4: the pending sign-in setup is dropped only once the mod
        # is out.
        step = body("CurUninstallStepChanged")
        self.assertLess(step.find("--uninstall-mod"), step.find("RegDeleteValue"))
        self.assertGreater(step.find("RegDeleteValue"), 0)

    def test_a_repeating_failure_can_be_uninstalled_anyway(self):
        # Review M2: the exit code the script tells apart is the helper's.
        step = body("CurUninstallStepChanged")
        codes = {int(n) for n in re.findall(r"ResultCode\s*=\s*(\d+)", step)}
        self.assertIn(app.UNINSTALL_ERROR, codes)
        self.assertIn("MB_YESNO", step)

    def test_the_old_uninstall_run_entry_is_not_back(self):
        # Negative twin of the move: [UninstallRun] ignores exit codes.
        self.assertNotRegex(ISS, r"(?m)^\[UninstallRun\]")


if __name__ == "__main__":
    unittest.main()
