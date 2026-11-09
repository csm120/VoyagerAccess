"""A point's detail panel does not repeat the name the player just heard.

Casey, 2026-11-08, his own play: Enter on "Debris Field, not scanned, 7 cycles
away, 11 of 18" said "Debris Field, in system 7 4 7 2 point 1. Scan celestial
body to collect data.", and the scan said "Scanning Debris Field" then
"Debris Field, in system 7 4 7 2 point 1. Resources: Deuterium, ...". Runs the
real popups.lua under lupa. This proves the trimming rule only; that the
speak step calls it is checked by hearing it in the game.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

STUBS = r"""
package.preload["speech"] = function() return { say = function() end } end
package.preload["screen"] = function() return { shown = function() return true end } end
package.preload["crumb"] = function() return setmetatable({}, { __index = function() return function() end end }) end
function FindAllOf() return {} end
function StaticFindObject() return nil end
function RegisterHook() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay(_, fn) fn() end
function LoopAsync() end
"""

P = "/Engine/Transient.GameEngine_1:BP_STVGameInstance_C_1.WBP_HUD_C_1.WidgetTree_1.POIDetailView"
ENTER = "Debris Field, in system 7 4 7 2 point 1. Scan celestial body to collect data."
SCANNED = ("Debris Field, in system 7 4 7 2 point 1. Resources: Deuterium, amount unknown "
           "until Stellar Cartography is upgraded")


@unittest.skipIf(lupa is None, "lupa not installed")
class PoiRepeatTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('popups'))")

    def test_enter_drops_the_name_keeps_the_system(self):
        self.M.poi_heard("Debris Field", "select")
        self.assertEqual(self.M.poi_trim(ENTER, P),
                         "In system 7 4 7 2 point 1. Scan celestial body to collect data.")

    def test_scan_drops_name_and_system(self):
        self.M.poi_heard("Debris Field", "scan")
        self.assertEqual(self.M.poi_trim(SCANNED, P),
                         "Resources: Deuterium, amount unknown until Stellar Cartography is upgraded")

    def test_used_once(self):
        self.M.poi_heard("Debris Field", "scan")
        self.M.poi_trim(SCANNED, P)
        self.assertEqual(self.M.poi_trim(SCANNED, P), SCANNED)

    # Negative twins: nothing heard, another point, another window.
    def test_nothing_heard_keeps_all(self):
        self.assertEqual(self.M.poi_trim(ENTER, P), ENTER)

    def test_other_point_keeps_all(self):
        self.M.poi_heard("Ship Wreck", "select")
        self.assertEqual(self.M.poi_trim(ENTER, P), ENTER)

    def test_other_window_keeps_all(self):
        self.M.poi_heard("Debris Field", "select")
        self.assertEqual(self.M.poi_trim(ENTER, P.replace("POIDetailView", "WBP_RoomPrompt_C_1")), ENTER)


if __name__ == "__main__":
    unittest.main()
