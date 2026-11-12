"""focus.lua: the ring hover hook climbs to the class that defines BP_OnHovered.

Fable review, 2026-11-10 (mod low 13): StaticFindObject returns an invalid
object, not nil, when nothing matches (Gotcha 3), so `if
StaticFindObject(fpath) then` was always true and install_ring_hover tried
the segment's own class and stopped there, never climbing. And its
GetSuperStruct loop had no depth limit (Gotcha 2). Runs the real focus.lua
under lupa with the stubs of test_lua_escape_repeat.
"""
import unittest

from tests.test_lua_escape_repeat import SCRIPTS, STUBS, lupa

EXTRA = r"""
hooked = {}
function RegisterHook(name, fn) hooked[#hooked + 1] = name return 1, 2 end
local missing = { IsValid = function() return false end }
local found = { IsValid = function() return true end }
defined = { ["/Game/UI/WBP_RadialSegmentBase.WBP_RadialSegmentBase_C:BP_OnHovered"] = true }
function StaticFindObject(p) if defined[p] then return found end return missing end
local function class(name, super)
    local c = { IsValid = function() return true end,
        GetFullName = function() return "WidgetBlueprintGeneratedClass /Game/UI/" .. name .. "." .. name .. "_C" end }
    c.GetSuperStruct = function() return super() end
    return c
end
local base
base = class("WBP_RadialSegmentBase", function() return nil end)
local child = class("WBP_RadialButton", function() return base end)
looped = nil
looped = class("WBP_Loop", function() return looped end)
function segment(c) return { GetClass = function() return c end } end
child_segment = segment(child)
loop_segment = segment(looped)
function find_install(M)
    local seen = {}
    local function up(fn)
        if seen[fn] then return nil end
        seen[fn] = true
        for i = 1, 255 do
            local n, v = debug.getupvalue(fn, i)
            if n == nil then break end
            if n == "install_ring_hover" then return v end
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
class ClassClimbTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.lua.execute(EXTRA)
        self.M = self.lua.execute("return (require('focus'))")
        self.install = self.lua.globals().find_install(self.M)
        self.assertIsNotNone(self.install)

    def hooked(self):
        return list(self.lua.globals().hooked.values())

    def test_climbs_to_the_parent_that_defines_the_event(self):
        self.install(self.lua.globals().child_segment)
        self.assertEqual(self.hooked(), ["/Game/UI/WBP_RadialSegmentBase.WBP_RadialSegmentBase_C:BP_OnHovered"])

    def test_own_definition_is_used_first(self):
        # Negative twin: a class that defines the event itself is hooked there.
        self.lua.execute('defined["/Game/UI/WBP_RadialButton.WBP_RadialButton_C:BP_OnHovered"] = true')
        self.install(self.lua.globals().child_segment)
        self.assertEqual(self.hooked(), ["/Game/UI/WBP_RadialButton.WBP_RadialButton_C:BP_OnHovered"])

    def test_a_class_chain_that_loops_ends(self):
        self.install(self.lua.globals().loop_segment)
        self.assertEqual(self.hooked(), [])


if __name__ == "__main__":
    unittest.main()
