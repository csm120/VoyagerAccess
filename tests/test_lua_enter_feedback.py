"""Enter that the game takes without a change says so.

Casey, 2026-11-09 ("yes to both"):
1. A conversation line the game holds (Chardis, 2026-11-08: Enter ignored
   for about three minutes, nothing said) says "The line has not moved on
   yet."
2. Enter on a choice already in use (the Mess Hall's "Normal Food Rations,
   selected", 2026-11-08) says "Already selected."
Runs the real speech.lua and dialogue.lua under lupa (the rules only).
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

STUBS = r"""
print = function() end
clock = 100
os.clock = function() return clock end
package.preload["tr"] = function()
    return { line = function(s) return s end, word = function(s) return s end, fill = function(s) return s end }
end
io.open = function()
    return { write = function(self) return self end, close = function() end, flush = function() end,
             seek = function() return 0 end, read = function() return nil end,
             lines = function() return function() return nil end end }
end
package.preload["screen"] = function() return { shown = function() return true end } end
package.preload["crumb"] = function() return setmetatable({}, { __index = function() return function() end end }) end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class EnterFeedbackTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.speech = self.lua.execute("return (require('speech'))")

    def test_said_since_sees_a_line_after_the_key(self):
        self.lua.execute("clock = 200")
        self.speech.say("Chardis: They're here!", True)
        self.assertTrue(self.speech.said_since(199.5))

    def test_said_since_ignores_lines_before_the_key(self):
        self.lua.execute("clock = 200")
        self.speech.say("Chardis: They're here!", True)
        self.assertFalse(self.speech.said_since(201))

    def test_line_held_when_the_same_line_is_still_up(self):
        d = self.lua.execute("return (require('dialogue'))")
        self.assertTrue(d.line_held("Chardis|They're here!", "Chardis|They're here!"))

    # VM, 2026-11-09: Janeway's "I'll second that..." moved on to Carey's
    # line 1.38 s after Enter (a scene change to Engineering), and the 1.2 s
    # check said "The line has not moved on yet." first. The wait must
    # outlast a scene change; the held line it is for lasted minutes. This
    # proves the constant only; that the timer uses it is checked by hearing.
    def test_wait_outlasts_a_scene_change(self):
        d = self.lua.execute("return (require('dialogue'))")
        self.assertGreaterEqual(d.HELD_MS, 3000)

    def test_line_not_held_when_it_moved_on_or_closed(self):
        d = self.lua.execute("return (require('dialogue'))")
        self.assertFalse(d.line_held("Chardis|They're here!", "Chardis|If anyone is receiving this"))
        self.assertFalse(d.line_held("Chardis|They're here!", None))
        self.assertFalse(d.line_held(None, None))


if __name__ == "__main__":
    unittest.main()
