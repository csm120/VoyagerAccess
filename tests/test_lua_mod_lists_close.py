"""The mod's own lists close when an event, a conversation or the main menu comes up.

Fable review, 2026-11-10 (mod finding 3), Casey's answer the same day: the
C, Ctrl+F1, Ctrl+F12 and J lists stayed open when the screen under them
changed, so the arrows kept reading the list while an event window or a
conversation waited, unnamed. They now close without a word on an event
window, a conversation window and the main menu; a toast leaves them open.

Runs the real focus.lua (the popups hooks) and dialogue.lua (a new
conversation window) under lupa; the four list modules are stubs that
record being closed.
"""
import unittest

from tests.test_lua_escape_repeat import SCRIPTS, lupa

STUBS = r"""
closed = {}
read_fns, widget_fns = {}, {}
local function list(name, open_fn, dismiss_fn)
    local m = { is_open = true }
    m[open_fn] = function() return m.is_open end
    m[dismiss_fn] = function() m.is_open = false closed[#closed + 1] = name end
    return setmetatable(m, { __index = function() return function() end end })
end
lists = {
    whatsnew = list("whatsnew", "open", "dismiss"),
    hotkeys = list("hotkeys", "open", "dismiss"),
    resources = list("resources", "list_open", "dismiss"),
    ship = list("ship", "list_open", "list_dismiss"),
}
for name, m in pairs(lists) do package.preload[name] = function() return m end end
local nop = setmetatable({}, { __index = function() return function() end end })
for _, m in ipairs({ "speech", "screen", "crumb", "keys", "construction", "text", "hints", "tr", "credits", "techtree" }) do
    package.preload[m] = function() return nop end
end
package.preload["keys"] = function() return setmetatable({ key_count = 0 }, { __index = function() return function() end end }) end
package.preload["popups"] = function()
    return setmetatable({ SAVE_WARNINGS = {}, ROOM_WARNINGS = {},
        on_read = function(fn) read_fns[#read_fns + 1] = fn end,
        on_widget = function(cls, fn) widget_fns[cls] = widget_fns[cls] or {} table.insert(widget_fns[cls], fn) end },
        { __index = function() return function() end end })
end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
function read(cls) for _, fn in ipairs(read_fns) do fn("/Engine/Transient.X:" .. cls .. "_1", cls) end end
function widget(cls) for _, fn in ipairs(widget_fns[cls] or {}) do fn("/Engine/Transient.X:" .. cls .. "_1") end end
function reopen() for _, m in pairs(lists) do m.is_open = true end closed = {} end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class ModListsCloseTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.focus = self.lua.execute("return (require('focus'))")
        self.focus.install()
        self.g = self.lua.globals()

    def closed(self):
        return sorted(self.g.closed.values())

    def test_event_window_closes_the_lists(self):
        self.g.read("WBP_POIMultipleChoice_C")
        self.assertEqual(self.closed(), ["hotkeys", "resources", "ship", "whatsnew"])

    def test_main_menu_closes_the_lists(self):
        self.g.widget("WBP_MainMenu_C")
        self.assertEqual(self.closed(), ["hotkeys", "resources", "ship", "whatsnew"])

    def test_conversation_closes_the_lists(self):
        self.focus.dismiss_mod_lists("conversation")
        self.assertEqual(self.closed(), ["hotkeys", "resources", "ship", "whatsnew"])

    def test_toast_leaves_the_lists_open(self):
        # Negative twin: a toast or report is read without closing them.
        self.g.read("WBP_Toast_C")
        self.g.read("WBP_TutorialInfoWidget_C")
        self.assertEqual(self.closed(), [])


if __name__ == "__main__":
    unittest.main()
