"""help.lua: a view line given up on after 20 busy looks is logged.

Fable review, 2026-11-10 (mod low 17): leaving() compares the game state
with the InGame value 3. If a patch renumbers the enum, the "Ship view" and
"System map" lines stop after 20 silent tries and nothing says why
(patch_check.py does not look at enum values). The give-up is now logged
once per view change. Runs the real help.lua under lupa; view_look's
helpers are replaced through its upvalues.
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
printed = {}
print = function(s) printed[#printed + 1] = s end
said = {}
package.preload["speech"] = function() return setmetatable({ say = function(t) said[#said + 1] = t end },
    { __index = function() return function() end end }) end
package.preload["popups"] = function() return setmetatable({ open_windows = function() return {} end, tutorial_closed_at = -100 },
    { __index = function() return function() end end }) end
for _, m in ipairs({ "screen", "crumb", "keys", "focus", "dialogue", "tr", "text", "hints", "awaymission", "techtree", "combat" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
delayed = {}
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay(ms, fn) delayed[#delayed + 1] = fn end
function LoopAsync() end
function run_delayed()
    for _ = 1, 60 do
        local d = delayed
        delayed = {}
        if #d == 0 then return end
        for _, fn in ipairs(d) do fn() end
    end
end
busy = true
local function up(fn, name, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 255 do
        local n, v = debug.getupvalue(fn, i)
        if n == nil then break end
        if n == name then return v, fn, i end
        if type(v) == "function" then
            local a, b, c = up(v, name, seen)
            if a ~= nil then return a, b, c end
        end
    end
end
function setup(M)
    local look
    for _, f in pairs(M) do
        if type(f) == "function" then look = look or up(f, "view_look") end
    end
    local _, fn, i = up(look, "view_now")
    debug.setupvalue(fn, i, function() return "ship" end)
    _, fn, i = up(look, "leaving")
    debug.setupvalue(fn, i, function() return busy end)
    return look
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class ViewBusyLoggedTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('help'))")
        self.look = self.lua.globals().setup(self.M)

    def printed(self):
        return [s for s in self.lua.globals().printed.values() if "view" in s]

    def test_give_up_is_logged(self):
        self.look()
        self.lua.globals().run_delayed()
        self.assertEqual(len([s for s in self.printed() if "not said" in s]), 1, self.printed())

    def test_quiet_view_that_settles_is_not_logged(self):
        # Negative twin: the game stops being busy, so the view is said.
        self.lua.globals().busy = False
        self.look()
        self.lua.globals().run_delayed()
        self.assertEqual([s for s in self.printed() if "not said" in s], [])


if __name__ == "__main__":
    unittest.main()
