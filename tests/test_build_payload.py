import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from installer import build_payload  # noqa: E402

# The vendored UE4SS release's own mods.txt.
VENDOR_MODS = """CheatManagerEnablerMod : 1
ConsoleCommandsMod : 1
ConsoleEnablerMod : 1
SplitScreenMod : 0
LineTraceMod : 0
BPML_GenericFunctions : 1
BPModLoaderMod : 1




; Built-in keybinds, do not move up!
Keybinds : 1
"""


class DevModsTests(unittest.TestCase):
    def test_developer_mods_are_switched_off(self):
        out = build_payload.player_mods_txt(VENDOR_MODS)
        for name in ("Keybinds", "ConsoleEnablerMod", "ConsoleCommandsMod", "CheatManagerEnablerMod"):
            self.assertIn(f"{name} : 0", out)
            self.assertNotIn(f"{name} : 1", out)

    def test_other_mods_and_order_are_kept(self):
        out = build_payload.player_mods_txt(VENDOR_MODS)
        self.assertIn("BPModLoaderMod : 1", out)
        self.assertIn("BPML_GenericFunctions : 1", out)
        # Keybinds must stay last (the file's own comment says so).
        self.assertTrue(out.rstrip().endswith("Keybinds : 0"))


if __name__ == "__main__":
    unittest.main()
