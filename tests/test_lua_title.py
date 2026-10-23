"""text.lua's title(): game names shown in capitals, said in title case.

combat.lua and quest.lua lowered a name and capitalised after every
character Lua's %a does not count as a letter, so "Kazon-Aufklärer" was
said "Kazon-AufkläRer" (firefly82's review, German game, 2026-10-23).
Runs the real text.lua under lupa.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

TEXT_LUA = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts" / "text.lua"


@unittest.skipIf(lupa is None, "lupa not installed")
class TitleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        cls.M = cls.lua.execute(TEXT_LUA.read_text(encoding="utf-8"))

    def title(self, s):
        return self.M.title(s)

    def test_english_capitals(self):
        self.assertEqual(self.title("KAZON RAIDER"), "Kazon Raider")

    def test_german_letter_inside_a_word(self):
        self.assertEqual(self.title("Kazon-Aufklärer"), "Kazon-Aufklärer")
        self.assertEqual(self.title("KAZON-AUFKLÄRER"), "Kazon-Aufklärer")

    def test_word_starting_with_an_accented_capital(self):
        self.assertEqual(self.title("ÉCLAIREUR KAZON"), "Éclaireur Kazon")

    def test_cyrillic(self):
        self.assertEqual(self.title("РАЗВЕДЧИК КАЗОНОВ"), "Разведчик Казонов")

    def test_polish(self):
        self.assertEqual(self.title("ZWIADOWCA ŁĄCZNOŚCI"), "Zwiadowca Łączności")

    def test_apostrophe_and_digits_stay_in_the_word(self):
        self.assertEqual(self.title("O'BRIEN'S 3RD SHIP"), "O'brien's 3rd Ship")

    def test_old_expression_had_the_reported_bug(self):
        # The negative twin: the expression combat.lua and quest.lua used.
        # Compared inside Lua: the old result is not always valid UTF-8.
        broken = self.lua.eval(
            "(function(s) local r = (s:lower():gsub(\"(%a)([%w']*)\", "
            "function(a, b) return a:upper() .. b end)) return r:sub(-3) == 'Rer' end)"
            "('Kazon-Aufkl\\195\\164rer')")
        self.assertTrue(broken)

    def test_not_a_string(self):
        self.assertEqual(self.title(""), "")


if __name__ == "__main__":
    unittest.main()
