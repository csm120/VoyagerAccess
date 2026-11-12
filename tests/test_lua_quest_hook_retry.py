"""quest.lua: a tracker class whose hooks could not go in is tried again.

Fable review, 2026-11-10 (mod low 17): hook_widget marked the class as
hooked before any hook was in, so a first try made before the class's
functions loaded was never repeated (view.lua fixed the same fault on
2026-10-21). Runs the real quest.lua under lupa.
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
print = function() end
for _, m in ipairs({ "speech", "screen", "crumb", "keys", "popups", "text", "tr", "ship" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
loaded = false
registered = {}
function RegisterHook(name, fn)
    if not loaded then error("function not found") end
    registered[#registered + 1] = name
    return 1, 2
end
local widget = { IsValid = function() return true end,
    GetClass = function() return { GetFullName = function() return "WidgetBlueprintGeneratedClass /Game/WBP_QuestTracker.WBP_QuestTracker_C" end } end }
function StaticFindObject() return widget end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
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
class QuestHookRetryTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('quest'))")
        self.M.request_look = lambda: None
        self.hook_widget = self.lua.globals().find_local(self.M, "hook_widget")
        self.assertIsNotNone(self.hook_widget)
        self.names = self.lua.table("UpdateQuests")

    def registered(self):
        return len(self.lua.globals().registered)

    def test_hooks_go_in_on_a_later_try(self):
        self.hook_widget("/Engine/Transient.X:Tracker", self.names)
        self.lua.execute("loaded = true")
        self.hook_widget("/Engine/Transient.X:Tracker", self.names)
        self.assertEqual(self.registered(), 1)

    def test_hooked_class_is_not_hooked_twice(self):
        # Negative twin.
        self.lua.execute("loaded = true")
        self.hook_widget("/Engine/Transient.X:Tracker", self.names)
        self.hook_widget("/Engine/Transient.X:Tracker", self.names)
        self.assertEqual(self.registered(), 1)


if __name__ == "__main__":
    unittest.main()
