"""system.lua: I does not report a trip the ship is no longer on.

Fable review, 2026-11-10 (mod finding 7): the trip record was cleared only
by OnTravelCompleted, so after Voyager was destroyed mid-trip, a save was
loaded or the main menu was reached, I still said "Traveling to ..., 73
percent of the way". And a move the mod could not name left the old trip
in place, so "Halfway to" named the old destination. Runs the real
system.lua under lupa; locals are reached through the module's upvalues.
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
print = function() end
said = {}
travelling = true
package.preload["tr"] = function()
    return { line = function(s) return s end, word = function(s) return s end, fill = function(s) return s end }
end
package.preload["speech"] = function()
    local function add(t) said[#said + 1] = t end
    return setmetatable({ say = add }, { __index = function() return function() end end })
end
for _, m in ipairs({ "screen", "crumb", "keys", "popups", "focus", "dialogue", "combat", "hints", "text", "events", "help" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
local journey = { IsValid = function() return true end, IsTravelling = function() return travelling end }
function FindFirstOf(cls) if cls == "STVJourneySubsystem" then return journey end end
function FindAllOf() return {} end
function StaticFindObject() return nil end
function RegisterHook() end
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
        if n == name then return v, fn, i end
        if type(v) == "function" then
            local a, b, c = up(v, name, seen)
            if a ~= nil then return a, b, c end
        end
    end
end
function set_trip(M, value)
    local _, fn, i = up(M.travel_status, "trip")
    debug.setupvalue(fn, i, value)
end
function get_trip(M)
    return (up(M.travel_status, "trip"))
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class TravelStatusTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('system'))")
        self.g = self.lua.globals()
        self.g.set_trip(self.M, self.lua.table_from({"name": "Class J Planet", "path": "/x", "progress": 0.73,
                                                    "half": True}))

    def test_trip_still_under_way_is_reported(self):
        # Negative twin: the ship is travelling, so I says so.
        self.assertEqual(self.M.travel_status(), "Traveling to Class J Planet, 73 percent of the way")

    def test_no_trip_once_the_ship_has_stopped(self):
        self.g.travelling = False
        self.assertIsNone(self.M.travel_status())
        self.assertIsNone(self.g.get_trip(self.M))


if __name__ == "__main__":
    unittest.main()
