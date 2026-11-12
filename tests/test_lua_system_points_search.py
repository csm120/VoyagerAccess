"""system.lua: listing the map's points asks once whether it is the Sector Map.

Fable review, 2026-11-10 (mod low 18): points() called M.sector(), a
FindAllOf of EnhancedInputLocalPlayerSubsystem, once per point inside its
loop, on the game thread, for every Up, Down and Enter on the map. Runs the
real system.lua under lupa with the stubs of test_lua_travel_status.
"""
import unittest

from tests.test_lua_travel_status import SCRIPTS, STUBS, lupa

EXTRA = r"""
searches = 0
local loc = { X = 0, Y = 0 }
local function poi(i)
    local actor = { bHidden = false, IsValid = function() return true end,
        GetClass = function() return { GetFName = function() return { ToString = function() return "BP_Planet_C" end } end } end,
        K2_GetActorLocation = function() return loc end,
        GetFullName = function() return "BP_Planet_C /Game/Map.Map:PersistentLevel.Planet_" .. i end,
        GetFName = function() return { ToString = function() return "Planet_" .. i end } end }
    return { IsValid = function() return true end, GetOwner = function() return actor end,
        GetFullName = function() return "STVPointOfInterestBase /Game/Map.Map:PersistentLevel.Poi_" .. i end }
end
local pois = { poi(1), poi(2), poi(3), poi(4), poi(5) }
function FindAllOf(cls)
    if cls == "STVPointOfInterestBase" then return pois end
    if cls == "EnhancedInputLocalPlayerSubsystem" then searches = searches + 1 end
    return {}
end
function find_points(M)
    for _, f in pairs(M) do
        if type(f) == "function" then
            local v = up_points(f)
            if v then return v end
        end
    end
end
function up_points(fn, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 255 do
        local n, v = debug.getupvalue(fn, i)
        if n == nil then break end
        if n == "points" then return v end
        if type(v) == "function" then
            local a = up_points(v, seen)
            if a then return a end
        end
    end
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class PointsSearchTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.lua.execute(EXTRA)
        self.M = self.lua.execute("return (require('system'))")
        self.points = self.lua.globals().find_points(self.M)
        self.assertIsNotNone(self.points)

    def test_one_search_for_five_points(self):
        got = self.points()
        self.assertEqual(len(got), 5)        # all listed (System Map, not a star system)
        self.assertEqual(self.lua.globals().searches, 1)


if __name__ == "__main__":
    unittest.main()
