"""Escape on a window it does not close says the window's button again.

0.4.0 did this for the mod's own button lists (a mission result with only
CONTINUE, Casey's play, 2026-11-08). VM, 2026-11-09: Escape on the Bridge's
side mission window ("Waste Disassembler", its own focused buttons) did not
close it and said nothing. Runs the real focus.lua under lupa
(escape_repeat_ok, the decision only; the 900 ms timer is checked by hearing).
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

STUBS = r"""
local nop = setmetatable({}, { __index = function() return function() end end })
for _, m in ipairs({ "speech", "screen", "crumb", "keys", "popups", "ship", "construction", "text", "hints", "tr" }) do
    package.preload[m] = function() return nop end
end
package.preload["popups"] = function()
    return setmetatable({ SAVE_WARNINGS = {}, ROOM_WARNINGS = {} }, { __index = function() return function() end end })
end
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
class EscapeRepeatTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('focus'))")

    def ok(self, **over):
        state = dict(same_key=True, pause=False, view_said=False, said=False, shown=True, same_focus=True)
        state.update(over)
        return self.M.escape_repeat_ok(self.lua.table_from(state))

    def test_window_still_up_and_silent_says_its_button(self):
        self.assertTrue(self.ok())

    # Negative twins: each reason to stay quiet.
    def test_quiet_when_the_pause_menu_opened(self):
        self.assertFalse(self.ok(pause=True))

    def test_quiet_when_the_window_closed(self):
        self.assertFalse(self.ok(shown=False))

    def test_quiet_when_the_view_was_said(self):
        self.assertFalse(self.ok(view_said=True))

    def test_quiet_when_something_else_spoke(self):
        self.assertFalse(self.ok(said=True))

    def test_quiet_after_another_key(self):
        self.assertFalse(self.ok(same_key=False))

    def test_quiet_when_focus_moved(self):
        self.assertFalse(self.ok(same_focus=False))


if __name__ == "__main__":
    unittest.main()
