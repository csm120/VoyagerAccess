"""popups.lua: hook_class stops climbing a class chain that loops.

Pre-merge review, 2026-11-10 (low 7.1): hook_class's GetSuperStruct loop got
a depth limit of 16 (Gotcha 2), but tests/test_lua_class_climb.py covers only
focus.lua's loops, so putting popups.lua back without the limit left every
test green. Runs the real popups.lua under lupa with the stubs of
test_lua_event_repeat. The stub class counts its ForEachFunction calls and
raises after 100, so a missing limit fails the test instead of hanging it.
"""
import unittest

from tests.test_lua_event_repeat import SCRIPTS, STUBS, lupa

EXTRA = r"""
walked = 0
local function class(name, full, super)
    local c = { IsValid = function() return true end }
    c.GetFName = function() return { ToString = function() return name end } end
    c.GetFullName = function() return "WidgetBlueprintGeneratedClass " .. full end
    c.ForEachFunction = function()
        walked = walked + 1
        if walked > 100 then error("class chain climbed without a limit") end
    end
    c.GetSuperStruct = function() return super() end
    return c
end
looped = nil
looped = class("WBP_TutorialInfoWidget_C", "/Game/UI/WBP_Loop.WBP_TutorialInfoWidget_C",
    function() return looped end)
local base = class("UserWidget", "/Script/UMG.UserWidget", function() return nil end)
plain = class("WBP_TutorialScreen1_C", "/Game/UI/WBP_TutorialScreen1.WBP_TutorialScreen1_C",
    function() return base end)
function find_hook_class(M)
    local seen = {}
    local function up(fn)
        if seen[fn] then return nil end
        seen[fn] = true
        for i = 1, 255 do
            local n, v = debug.getupvalue(fn, i)
            if n == nil then break end
            if n == "hook_class" then return v end
            if type(v) == "function" then
                local a = up(v)
                if a then return a end
            end
        end
    end
    for _, f in pairs(M) do
        if type(f) == "function" then
            local v = up(f)
            if v then return v end
        end
    end
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class PopupsClassClimbTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.lua.execute(EXTRA)
        self.M = self.lua.execute("return (require('popups'))")
        self.hook_class = self.lua.globals().find_hook_class(self.M)
        self.assertIsNotNone(self.hook_class, "hook_class not reachable from popups.lua's functions")

    def test_a_class_chain_that_loops_ends(self):
        self.assertTrue(self.hook_class(self.lua.globals().looped))
        self.assertEqual(self.lua.globals().walked, 16)

    def test_a_chain_ends_at_the_engine_base_class(self):
        # Negative twin: an ordinary chain is walked to the engine's own
        # UserWidget and stops there, well inside the limit.
        self.assertTrue(self.hook_class(self.lua.globals().plain))
        self.assertEqual(self.lua.globals().walked, 1)


if __name__ == "__main__":
    unittest.main()
