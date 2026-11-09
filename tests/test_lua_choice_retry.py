"""Enter on a choice that has only just appeared is clicked again if the game ignored it.

Casey's play, 2026-11-08 20:22:56: Enter on a choice about a second after a
Shift+Enter skip did nothing. VM, 2026-11-09 (Unity, sector 5): the choices
came up at 11:12:56.013, Enter at 56.050 logged "enter: choice", and the
game never took it (nothing for 20 s). Runs the real focus.lua under lupa
(choice_retry_ok, the decision only; the timer is checked by hearing).
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
class ChoiceRetryTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('focus'))")

    def ok(self, **over):
        s = dict(same_key=True, said=False, shown=True, same_label=True)
        s.update(over)
        return self.M.choice_retry_ok(self.lua.table_from(s))

    def test_ignored_click_is_clicked_again(self):
        self.assertTrue(self.ok())

    # Negative twins: the choice was taken (hidden, or the next line spoke),
    # or the player pressed something else.
    def test_taken_choice_is_left_alone(self):
        self.assertFalse(self.ok(shown=False))

    def test_a_line_after_the_click_means_it_was_taken(self):
        self.assertFalse(self.ok(said=True))

    # Fable review: the next choices can come back on the same button
    # unheard (distress call, 2026-10-15); a different label is not clicked.
    def test_a_new_choice_on_the_same_button_is_not_clicked(self):
        self.assertFalse(self.ok(same_label=False))

    def test_another_key_wins(self):
        self.assertFalse(self.ok(same_key=False))


if __name__ == "__main__":
    unittest.main()
