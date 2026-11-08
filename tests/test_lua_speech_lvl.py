"""speech.lua: the game's "Lvl" abbreviation is said as "level".

"Stellar Cartography Lvl 1" on a dialogue choice was read as "Lvl"
(Casey's play, 2026-11-07); events.lua expanded it only for its own
requirement lines. Runs the real speech.lua under lupa and reads what it
writes to speech.txt.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"


@unittest.skipIf(lupa is None, "lupa not installed")
class LvlTests(unittest.TestCase):
    def said(self, text):
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        lua.execute('''
            written = {}
            print = function() end
            package.preload["tr"] = function()
                return { line = function(s) return s end, word = function(s) return s end,
                         fill = function(s) return s end }
            end
            io.open = function(p, m)
                return { write = function(self, ...) for _, s in ipairs({...}) do written[#written + 1] = s end return self end,
                         close = function() end, flush = function() end, seek = function() return 0 end,
                         read = function() return nil end, lines = function() return function() return nil end end }
            end
        ''')
        M = lua.execute("return (require('speech'))")
        M.say(text, True)
        return "".join(lua.globals().written.values())

    def test_lvl_before_a_number_is_level(self):
        out = self.said("Optional: Do a general scan of the planet. Stellar Cartography Lvl 1.")
        self.assertIn("Stellar Cartography level 1", out)
        self.assertNotIn("Lvl", out)

    def test_other_words_are_left_alone(self):
        out = self.said("Lvlx Calvlvl 3")
        self.assertIn("Lvlx", out)


if __name__ == "__main__":
    unittest.main()
