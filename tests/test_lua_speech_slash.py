"""speech.lua: a number, a slash and a number is said "N of M".

Skills review, 2026-11-07, item 2: the game's texts put a slash between
numbers ("Integrity: {Current} / {Max}", "(3/5)", "active 0/10"), and with
punctuation off a screen reader says "40 100". Runs the real speech.lua and
tr.lua under lupa with the game's culture stubbed, and reads speech.txt.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"


@unittest.skipIf(lupa is None, "lupa not installed")
class SlashTests(unittest.TestCase):
    def said(self, text, culture="en"):
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        lua.execute('''
            written = {}
            print = function() end
            culture = ...
            function StaticFindObject()
                return { GetCurrentCulture = function() return { ToString = function() return culture end } end,
                         IsValid = function() return true end }
            end
            package.preload["language"] = function()
                return { english = function() return culture == "en" end }
            end
            io.open = function(p, m)
                return { write = function(self, ...) for _, s in ipairs({...}) do written[#written + 1] = s end return self end,
                         close = function() end, flush = function() end, seek = function() return 0 end,
                         read = function() return nil end, lines = function() return function() return nil end end }
            end
        ''')
        lua.globals().culture = culture
        M = lua.execute("return (require('speech'))")
        M.say(text, True)
        return "".join(lua.globals().written.values())

    def test_spaced_slash(self):
        self.assertIn("Integrity: 40 of 100", self.said("Integrity: 40 / 100"))

    def test_tight_slash_in_brackets(self):
        self.assertIn("Scan the planets (3 of 5)", self.said("Scan the planets (3/5)"))

    def test_german_word(self):
        self.assertIn("40 von 100", self.said("Integrität: 40 / 100", "de"))

    def test_japanese_count_wording(self):
        # Its own "{n} out of {n}": "4中3", not the line pass's "3、最大4"
        # (Fable review, 2026-11-25: "3/4ほどが" is three quarters).
        self.assertIn("4中3ほどが", self.said("3/4ほどが", "ja"))

    def test_chinese_count_not_list_position(self):
        out = self.said("有3/4的生物正在奔向自由", "zh-Hans")
        self.assertIn("4中的3", out)
        self.assertNotIn("第", out)

    def test_chain_is_left_whole(self):
        self.assertIn("1/2/3", self.said("Steps 1/2/3"))

    def test_spaced_chain_is_left_whole(self):
        # Fable review, 2026-11-25: "10 of 20 / 30".
        self.assertIn("10 / 20 / 30", self.said("Tiers 10 / 20 / 30"))

    def test_float_noise_before_a_narrow_space(self):
        # French writes U+202F before %.
        out = self.said("ajoute 26,999998 % de bonus", "fr")
        self.assertNotIn("999998", out)

    def test_float_noise_is_rounded(self):
        # The Sickbay's own report: "Assigned hero adds a 26.999998% bonus."
        # (Casey's play, 2026-11-25; found by tools/speech_rules.py).
        out = self.said("Assigned hero adds a 26.999998% bonus.")
        self.assertIn("adds a 27% bonus", out)

    def test_float_noise_with_comma_and_space(self):
        # French and German write "26,999998 %" (GPT review, 2026-11-25).
        self.assertIn("ajoute 27 % de bonus", self.said("ajoute 26,999998 % de bonus", "fr"))
        self.assertIn("um 33,3 %", self.said("um 33,333333 %", "de"))

    def test_short_decimals_stay(self):
        # Negative twin: a real decimal the game shows is left alone.
        self.assertIn("2.5%", self.said("Crit chance 2.5%"))
        self.assertIn("version 1.0234", self.said("version 1.0234"))

    def test_slash_between_words_is_left(self):
        # Negative twin: only numbers on both sides.
        out = self.said("Shields/Weapons online")
        self.assertIn("Shields/Weapons", out)
        self.assertNotIn(" of ", out)


if __name__ == "__main__":
    unittest.main()
