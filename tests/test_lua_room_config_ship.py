"""construction.lua: room figures come from the ship's own room config.

The Q Trials Equinox has its own STVRoomConfig (DA_RoomConfig_Equinox), and
the game's construction manager holds the one in use (RoomConfig). The mod
read the campaign's DA_RoomConfig by path, so on the Equinox a room's
footprint and costs were Voyager's (mode guard review, 2026-11-25, item A1).
Runs the real construction.lua under lupa.
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
for _, m in ipairs({ "speech", "crumb", "keys", "focus", "help", "tr", "text", "hints", "screen", "popups", "rooms", "ship" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
local function config(x, y)
    return { IsValid = function() return true end,
             GetRoomConfig = function(self, t, lvl, out) out.OutConfig = { Extent = { X = x, Y = y } } end }
end
campaign = config(3, 1)
equinox = config(5, 1)
manager = nil
function StaticFindObject(path) if path:find("DA_RoomConfig", 1, true) then return campaign end end
function FindFirstOf(cls) if cls == "STVConstructionManager" then return manager end end
function FindAllOf() return {} end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class RoomConfigShipTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('construction'))")

    def test_equinox_config_from_the_manager(self):
        self.lua.execute("manager = { IsValid = function() return true end, RoomConfig = equinox }")
        self.assertEqual(self.M.extent(5), (5, 1))

    def test_campaign_config_without_a_manager(self):
        # Negative twin: no manager found, the campaign's config by path.
        self.assertEqual(self.M.extent(5), (3, 1))


if __name__ == "__main__":
    unittest.main()
