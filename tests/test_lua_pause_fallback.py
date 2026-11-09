"""Closing the pause menu over a window says the window, not nothing.

VM, 2026-11-09: over an away mission's outcome (Mission complete ...
CONTINUE), Escape opened the pause menu ("RESUME, 1 of 5") and the second
Escape closed it in silence: the close asks for the view again, and over a
window the view is "other", which says nothing. Runs the real focus.lua
under lupa (pause_fallback, the decision only; the timer is checked by
hearing).
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
class PauseFallbackTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('focus'))")

    def pick(self, **s):
        state = dict(view_said=False, said=False, virtual=False, focus_shown=False)
        state.update(s)
        return self.M.pause_fallback(self.lua.table_from(state))

    def test_window_list_says_its_button(self):
        self.assertEqual(self.pick(virtual=True), "window")

    def test_focused_button_is_said(self):
        self.assertEqual(self.pick(focus_shown=True), "focus")

    def test_otherwise_the_line_or_result(self):
        self.assertEqual(self.pick(), "line")

    # Negative twins: the view line or anything else already spoke.
    def test_quiet_after_the_view_line(self):
        self.assertIsNone(self.pick(view_said=True, virtual=True))

    def test_quiet_when_something_else_spoke(self):
        self.assertIsNone(self.pick(said=True, focus_shown=True))

    # VM, 2026-11-09, an event's option: the game's focus came back and was
    # said between the Escape and the moment the mod saw the menu gone, and
    # the fallback said it a second time. "Said" counts from the Escape:
    # view_after_pause keeps the key's time for pause_fallback.
    def test_spoken_since_the_escape_counts(self):
        self.lua.execute("package.loaded['speech'] = nil")
        self.lua.execute("""
            local spoke_at = 10
            package.preload['speech'] = function()
                return setmetatable({ said_since = function(t) return spoke_at >= t end },
                    { __index = function() return function() end end })
            end
        """)
        self.assertTrue(self.M.pause_said(9.5))    # Escape at 9.5, the option at 10
        self.assertFalse(self.M.pause_said(10.5))  # nothing after a later key


if __name__ == "__main__":
    unittest.main()
