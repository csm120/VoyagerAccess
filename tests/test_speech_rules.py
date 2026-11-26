"""tools/speech_rules.py: the rules check can pass and can fail."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
try:
    import speech_rules  # noqa: E402
except ImportError:   # the public copy leaves the development tools out
    speech_rules = None


@unittest.skipIf(speech_rules is None, "tools/speech_rules.py is not in this copy")
class SpeechRulesTests(unittest.TestCase):
    def setUp(self):
        self.rules = speech_rules.load_rules(speech_rules.RULES)

    def broken(self, *lines):
        return speech_rules.check(list(lines), self.rules)

    def test_shipped_rules_load(self):
        self.assertGreater(len(self.rules), 5)

    def test_clean_lines_pass(self):
        self.assertEqual(self.broken("Ship view. Deck 5, Sick bay, on, The Doctor",
                                     "Integrity: 40 of 100", "Choice 1 of 3: Defend yourself.",
                                     "Species 8 4 7 2", "Wait..."), {})

    def test_each_fault_fails(self):
        for line in ("Defeated {0} Bosses!", "Weapons 0 of 0", "Integrity 40/100", "#trade blocked text",
                     "Tech_Crew_SickBay_SickBayLevel2_Name", "two times).. With",
                     "adds a 26.999998% bonus", "Stellar Cartography Lvl 1", "Species 8472"):
            self.assertTrue(self.broken(line), line)

    def test_expect_rule(self):
        self.assertTrue(self.broken("Choice 2 of 3"))

    def test_placeholders_from_the_game_log(self):
        with tempfile.TemporaryDirectory() as d:
            log = Path(d) / "UE4SS.log"
            log.write_text("[x] [Lua] [VoyagerAccess] placeholder: {AlliedShipInitialCost}\n[x] other {y}\n",
                           encoding="utf-8")
            self.assertEqual(speech_rules.placeholders(log), {"{AlliedShipInitialCost}": 1})
            sp = Path(d) / "speech.txt"
            sp.write_text("I|fine\n", encoding="utf-8")
            self.assertEqual(speech_rules.main([str(sp), "--ue4ss", str(log)]), 1)
            log.write_text("[x] other\n", encoding="utf-8")
            self.assertEqual(speech_rules.main([str(sp), "--ue4ss", str(log)]), 0)

    def test_nvda_double_quoted_line(self):
        with tempfile.TemporaryDirectory() as d:
            log = Path(d) / "nvda.log"
            log.write_text('Speaking ["B\'Elanna: Integrity 40/100"]\nSpeaking [\'Ship view\']\n', encoding="utf-8")
            self.assertEqual(speech_rules.nvda_lines(log), ["B'Elanna: Integrity 40/100", "Ship view"])

    def test_exit_code(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "speech.txt"
            p.write_text("I|Integrity: 40 of 100\n", encoding="utf-8")
            self.assertEqual(speech_rules.main([str(p)]), 0)
            p.write_text("I|Integrity: 40 of 100\nQ|Weapons 0 of 0\n", encoding="utf-8")
            self.assertEqual(speech_rules.main([str(p)]), 1)


if __name__ == "__main__":
    unittest.main()
