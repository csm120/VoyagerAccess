"""text.lua's prep(): a cycle icon right after the game's own cycle word.

The game writes the word before the icon in every language ("pro ZYKLUS
<img id="Cycles"/>", 31 times in German; "в цикл", "サイクル", "每周期").
Only an English word was recognised, so German heard "pro ZYKLUS Zyklus"
(firefly82's review, 2026-10-29). Runs the real text.lua under lupa.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

TEXT_LUA = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts" / "text.lua"
ICON = '<img id="Cycles"/>'


@unittest.skipIf(lupa is None, "lupa not installed")
class CycleIconTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        # The game's resource manager is absent; tr.word gives German.
        cls.lua.execute(
            'package.preload["tr"] = function() return { word = function(w) '
            'return ({ cycle = "Zyklus", cycles = "Zyklen" })[w] or w end } end')
        cls.M = cls.lua.execute(TEXT_LUA.read_text(encoding="utf-8"))

    def prep(self, s):
        return self.M.prep(s)

    def test_german_word_before_icon(self):
        self.assertEqual(self.prep("-6 HÜLLE pro ZYKLUS " + ICON), "-6 HÜLLE pro ZYKLUS")

    def test_german_word_in_colour_tag(self):
        self.assertNotIn("Zyklus", self.prep("+2 pro <ColorCycles>ZYKLUS</> " + ICON))

    def test_german_plural(self):
        self.assertEqual(self.prep("alle 3 ZYKLEN " + ICON), "alle 3 ZYKLEN")

    def test_russian(self):
        self.assertEqual(self.prep("-2 в цикл " + ICON), "-2 в цикл")

    def test_russian_plural_ending_in_a_byte_lua_called_a_digit(self):
        self.assertEqual(self.prep("[9 циклов " + ICON + "]"), "[9 циклов]")

    def test_japanese_no_space(self):
        self.assertEqual(self.prep("3サイクル" + ICON), "3サイクル")

    def test_chinese(self):
        self.assertEqual(self.prep("-2 每周期" + ICON), "-2 每周期")

    def test_english_still_dropped(self):
        self.assertEqual(self.prep("-2 per CYCLE " + ICON), "-2 per CYCLE")

    # The negative twins: an icon with no word before it still becomes one.
    def test_german_per_alone_still_named(self):
        self.assertEqual(self.prep("-6 HÜLLE pro " + ICON), "-6 HÜLLE pro Zyklus")

    def test_number_then_icon_still_named(self):
        self.assertEqual(self.prep("in 3 " + ICON), "in 3 Zyklen")


if __name__ == "__main__":
    unittest.main()
