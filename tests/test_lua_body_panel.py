"""A planet's or ship's own detail panel names its system as the point panel does.

0.4.0's VM walk (demo): a ship point's panel (WBP_ShipDetailView_C) said
"System. 4,832.0" raw. VM, 2026-11-09 (full game): WBP_PlanetDetailView_C
read "Class Y Planet. System. 1,616.0. Cold-Zone". These two classes are
watched by name, so they never got the point panel's layout. Runs the real
popups.lua under lupa (text_from by class).
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
noted = nil
package.preload["system"] = function()
    return {
        spoken_number = function(s) return (s:gsub("%.0$", ""):gsub(",", ""):gsub("(%d)", "%1 "):gsub(" $", "")) end,
        note_found = function(s) noted = s end,
    }
end
cls = "WBP_ShipDetailView_C"
local w = {}
function w:IsValid() return true end
function w:GetClass() return { GetFName = function() return { ToString = function() return cls end } end } end
function FindAllOf() return {} end
function StaticFindObject() return w end
function RegisterHook() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay(_, fn) fn() end
function LoopAsync() end
"""

P = "/Engine/Transient.X:WBP_ShipDetailView_C_1"


@unittest.skipIf(lupa is None, "lupa not installed")
class BodyPanelTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('popups'))")

    def parts(self, *pairs):
        t = self.lua.table()
        for i, (name, text) in enumerate(pairs, 1):
            t[i] = self.lua.table_from({"name": name, "text": text, "i": i, "path": P + "." + name})
        return t

    def test_ship_panel_names_the_system(self):
        out = self.M.text_from(self.parts(("LocationNameTextBlock", "Kazon Fighter"),
                                          ("ShipClassTextBlock", "Raider"),
                                          ("System_TextBLock", "System"),
                                          ("SystemNameTextBlock", "4,832.0"),
                                          ("StatusTextBlock", "Online")), P)
        self.assertEqual(out, "Kazon Fighter, in system 4 8 3 2. Raider. Online")

    def test_planet_panel_names_the_system(self):
        self.lua.execute("cls = 'WBP_PlanetDetailView_C'")
        out = self.M.text_from(self.parts(("LocationNameTextBlock", "Class Y Planet"),
                                          ("Population_1", "System"),
                                          ("SystemNameTextBlock", "1,616.0"),
                                          ("PlanetStarZoneTextBlock", "Cold-Zone")), P)
        self.assertEqual(out, "Class Y Planet, in system 1 6 1 6. Cold-Zone")

    # VM, 2026-11-09 (demo): a ship wreck's panel is a third class with the
    # same fields, and read "Ship Wreck. System. 8,112.0".
    def test_generic_location_panel_names_the_system(self):
        self.lua.execute("cls = 'WBP_GenericLocationDetailView_C'")
        out = self.M.text_from(self.parts(("LocationNameTextBlock", "Ship Wreck"),
                                          ("System_TextBLock", "System"),
                                          ("SystemNameTextBlock", "8,112.0")), P)
        self.assertEqual(out, "Ship Wreck, in system 8 1 1 2")

    # Fable review: in another language the label is not "System"; it is
    # dropped by its name, as poi_detail drops System_TextBLock.
    def test_translated_label_is_dropped(self):
        out = self.M.text_from(self.parts(("LocationNameTextBlock", "Chasseur Kazon"),
                                          ("System_TextBLock", "Système"),
                                          ("SystemNameTextBlock", "4,832.0"),
                                          ("StatusTextBlock", "En ligne")), P)
        self.assertEqual(out, "Chasseur Kazon, in system 4 8 3 2. En ligne")
        self.lua.execute("cls = 'WBP_PlanetDetailView_C'")
        out = self.M.text_from(self.parts(("LocationNameTextBlock", "Planète"),
                                          ("Population_1", "Système"),
                                          ("SystemNameTextBlock", "1,616.0")), P)
        self.assertEqual(out, "Planète, in system 1 6 1 6")

    # The map list's "found" note stays the point panel's: a sub-panel's
    # status ("Online") is not something the point holds.
    def test_sub_panel_notes_nothing_found(self):
        self.M.text_from(self.parts(("LocationNameTextBlock", "Kazon Fighter"),
                                    ("SystemNameTextBlock", "4,832.0"),
                                    ("StatusTextBlock", "Online")), P)
        self.assertIsNone(self.lua.eval("noted"))


if __name__ == "__main__":
    unittest.main()
