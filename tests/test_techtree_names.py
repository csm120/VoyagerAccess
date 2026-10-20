"""techtree.lua's clean_name joins a technology name the game wraps inside
its field. The German game breaks words with a hyphen at the line end:
"Verhandlungs-" then "taktiken" is one word (heard "Verhandlungs-taktiken",
VM, 2026-10-20), while "Deuterium-" then "Abfall..." keeps its real hyphen
(firefly82's review, 2026-10-19). The local function is cut out of the file
and run through lupa; skipped when lupa is not installed."""
import re
import unittest
from pathlib import Path

try:
    import lupa
except ImportError:
    lupa = None

TECHTREE = Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts" / "techtree.lua"


@unittest.skipIf(lupa is None, "lupa not installed")
class CleanNameTests(unittest.TestCase):
    def setUp(self):
        src = TECHTREE.read_text(encoding="utf-8")
        m = re.search(r"^local function clean_name\(s\)\n.*?^end\n", src, re.S | re.M)
        self.assertIsNotNone(m, "clean_name not found in techtree.lua")
        lua = lupa.LuaRuntime()
        self.clean = lua.execute(m.group(0) + "\nreturn clean_name")

    def test_layout_hyphen_before_lowercase_goes(self):
        self.assertEqual(self.clean("Verhandlungs-\ntaktiken"), "Verhandlungstaktiken")
        self.assertEqual(self.clean("Material-\r\nrückgewinnung"), "Materialrückgewinnung")

    def test_real_hyphen_before_capital_stays(self):
        self.assertEqual(self.clean("Deuterium-\nAbfallreduzierung"), "Deuterium-Abfallreduzierung")
        self.assertEqual(self.clean("Deuterium-Abfall-\nreduzierung"), "Deuterium-Abfallreduzierung")

    def test_other_breaks_are_spaces(self):
        self.assertEqual(self.clean("Small\nBattery Unit"), "Small Battery Unit")


if __name__ == "__main__":
    unittest.main()
