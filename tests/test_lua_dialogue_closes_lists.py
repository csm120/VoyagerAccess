"""dialogue.lua: a new conversation window closes the mod's own lists.

Fable review, 2026-11-10 (mod finding 3), Casey's answer the same day. The
window events are driven as the game calls them (on_window, reached
through the module's upvalues); focus.lua is a stub recording the call.
Uses the stubs of test_lua_dialogue_late_look.
"""
import unittest

from tests.test_lua_dialogue_late_look import SCRIPTS, STUBS, lupa

EXTRA = r"""
dismissed = {}
package.preload["focus"] = function()
    return setmetatable({ dismiss_mod_lists = function(why) dismissed[#dismissed + 1] = why end },
        { __index = function() return function() end end })
end
ctx = { get = function() return win end }
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class DialogueClosesListsTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.lua.execute(EXTRA)
        self.M = self.lua.execute("return (require('dialogue'))")
        self.g = self.lua.globals()
        self.on_window = self.g.find_local(self.M, "on_window")
        self.assertIsNotNone(self.on_window)

    def event(self, kind):
        self.on_window(kind)(self.g.ctx)

    def dismissed(self):
        return list(self.g.dismissed.values())

    def test_new_conversation_closes_the_lists(self):
        self.event("open")
        self.assertEqual(self.dismissed(), ["conversation"])

    def test_next_line_of_the_same_conversation_does_not(self):
        # Negative twin: only a window new to the mod closes them.
        self.event("open")
        self.event("typed")
        self.event("choices")
        self.assertEqual(self.dismissed(), ["conversation"])


if __name__ == "__main__":
    unittest.main()
