"""VoyagerAccess.iss: a silent update refuses while the game runs (Casey, 2026-11-10).

The setup itself can only be run in the VM, so this checks the script's
text: it names every game exe the helper knows (steam.GAME_EXES), writes the
update-deferred.txt the helper reads (app.UPDATE_DEFERRED), and refuses
only in silent runs. A renamed exe or file on one side would otherwise
leave the refusal silently doing nothing.
"""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from voyager import app, steam  # noqa: E402

ISS = (ROOT / "installer" / "VoyagerAccess.iss").read_text(encoding="utf-8")


def prepare_to_install():
    start = ISS.find("function PrepareToInstall")
    end = ISS.find("\nend;", start)
    return ISS[start:end] if start >= 0 else ""


class UpdateRefusalScriptTests(unittest.TestCase):
    def test_names_every_game_exe(self):
        for exe in steam.GAME_EXES:
            self.assertIn(exe, ISS)

    def test_writes_the_file_the_helper_reads(self):
        self.assertIn(app.UPDATE_DEFERRED.name, prepare_to_install())

    def test_refuses_only_when_silent(self):
        body = prepare_to_install()
        self.assertIn("WizardSilent", body)
        self.assertIn("GameRunning", body)


if __name__ == "__main__":
    unittest.main()
