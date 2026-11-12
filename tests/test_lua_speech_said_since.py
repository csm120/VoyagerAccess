"""speech.lua: said_since counts only lines that were really written.

Fable review, 2026-11-10 (mod finding 12): M.say recorded a line in
M.recent before deciding to drop it as a repeat, so said_since answered
true for a line never written to speech.txt, and the "say it again if
nothing was said" fallbacks (Escape repeat, pause menu, choice re-click)
stayed silent. Runs the real speech.lua under lupa.
"""
import unittest

from tests.test_lua_speech_lvl import SCRIPTS, lupa


@unittest.skipIf(lupa is None, "lupa not installed")
class SaidSinceTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute('''
            written = {}
            T = 100
            os.clock = function() return T end
            print = function() end
            package.preload["tr"] = function()
                return { line = function(s) return s end, word = function(s) return s end,
                         fill = function(s) return s end, apply = function(s) return s end }
            end
            io.open = function(p, m)
                return { write = function(self, ...) for _, s in ipairs({...}) do written[#written + 1] = s end return self end,
                         close = function() end, flush = function() end, seek = function() return 0 end,
                         read = function() return nil end, lines = function() return function() return nil end end }
            end
        ''')
        self.M = self.lua.execute("return (require('speech'))")
        self.g = self.lua.globals()

    def written(self):
        return "".join(self.g.written.values())

    def test_dropped_repeat_is_not_said(self):
        self.M.say("Resume", False)
        self.g.T = 100.5
        self.M.say("Resume", False)          # the same line again: dropped
        self.assertEqual(self.written().count("Resume"), 1)
        self.assertFalse(self.M.said_since(100.4))

    def test_empty_line_is_not_said(self):
        self.g.T = 101
        self.M.say("   ", False)
        self.assertFalse(self.M.said_since(100.9))

    def test_written_line_is_said(self):
        # Negative twin: a line that reached speech.txt still counts.
        self.M.say("Resume", False)
        self.g.T = 100.5
        self.M.say("Pause menu", False)
        self.assertTrue(self.M.said_since(100.4))
        self.assertIn("Pause menu", list(self.M.recent_lines(5).values()))


if __name__ == "__main__":
    unittest.main()
