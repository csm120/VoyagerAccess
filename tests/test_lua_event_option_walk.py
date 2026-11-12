"""events.lua: one failed look at an option button's class is not kept.

Fable review, 2026-11-10 (mod low 14): has_current was set to false before
the property walk and stayed false if the walk threw (the button torn down
as it was looked at), so every later option in the session went through
the GetOptionDescription scan that crashed the game 3 of 3. Runs the real
events.lua under lupa; option_for is reached through the module's upvalues.
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
print = function() end
scanned = 0
package.preload["tr"] = function()
    return { line = function(s) return s end, word = function(s) return s end, fill = function(s) return s end }
end
for _, m in ipairs({ "speech", "screen", "crumb", "keys", "popups", "focus", "dialogue", "hints", "text", "help", "system", "rooms", "ship" }) do
    package.preload[m] = function() return setmetatable({ prep = function(s) return s end },
        { __index = function() return function() end end }) end
end
function FindAllOf(cls)
    if cls == "STVPOIEventOption" then scanned = scanned + 1 end
    return {}
end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
option = { IsValid = function() return true end }
local prop = { GetFName = function() return { ToString = function() return "CurrentOption" end } end }
local class = { IsValid = function() return true end,
    ForEachProperty = function(self, fn) fn(prop) end, GetSuperStruct = function() return nil end }
torn = true
function make_button()
    return { CurrentOption = option,
        GetClass = function() if torn then error("torn down") end return class end }
end
local function up(fn, name, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 255 do
        local n, v = debug.getupvalue(fn, i)
        if n == nil then break end
        if n == name then return v end
        if type(v) == "function" then
            local a = up(v, name, seen)
            if a then return a end
        end
    end
end
function find_local(M, name)
    for _, f in pairs(M) do
        if type(f) == "function" then
            local v = up(f, name)
            if v then return v end
        end
    end
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class OptionWalkTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('events'))")
        self.g = self.lua.globals()
        self.option_for = self.g.find_local(self.M, "option_for")
        self.assertIsNotNone(self.option_for)
        self.same = self.lua.eval("function(a, b) return a == b end")

    def test_failed_walk_is_tried_again(self):
        self.option_for(self.g.make_button(), "Trade")       # torn down mid-look
        self.g.torn = False
        got = self.option_for(self.g.make_button(), "Trade")
        self.assertTrue(self.same(got, self.g.option))
        self.assertEqual(self.g.scanned, 0)

    def test_good_walk_uses_the_field(self):
        # Negative twin: a whole walk finds CurrentOption and never scans.
        self.g.torn = False
        self.assertTrue(self.same(self.option_for(self.g.make_button(), "Trade"), self.g.option))
        self.assertEqual(self.g.scanned, 0)


if __name__ == "__main__":
    unittest.main()
