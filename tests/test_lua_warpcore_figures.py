"""Every unlocked warp core tier says what it makes and burns.

Casey asked what Tier 2 would give him; the mod said just "Tier 2", while a
sighted player selects it and sees its figures in the "Currently selected
tier" panel before switching it on (his play, 2026-11-08). The figures come
from STVModifier_MainEngineering's PowerLevels (entry 1 is Gray Mode, read
live: 60, 120, 180 ... energy, 5 energy per deuterium). Runs the real
warpcore.lua under lupa.
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
cm = { selected = 1, max = 2 }
function cm:IsValid() return true end
function cm:GetSelectedWarpcoreLevel() return self.selected end
function cm:GetMaxSelectableWarpcoreLevel() return self.max end
function cm:GetWarpcoreInfo() return { WarpcoreEnergyOutputMax = 120 } end
function cm:GetEnergyProducedPerDeuterium() return 5 end
local levels = {}
for i, e in ipairs({ 60, 120, 180, 240 }) do
    levels[i] = { get = function() return { EnergyProductionPerCycle = e, EnergyProducedPerDeuterium = i == 1 and 0 or 5 } end }
end
mod = { PowerLevels = { ForEach = function(_, fn) for i, v in ipairs(levels) do fn(i, v) end end } }
function mod:IsValid() return true end
function FindFirstOf(c) if c == "STVConstructionManager" then return cm end end
function FindAllOf(c) if c == "STVModifier_MainEngineering" then return { mod } end return {} end
function StaticFindObject() return nil end
"""

P = "/Engine/Transient.X.WBP_MainEngineeringModule_C_1.WidgetTree_1."


@unittest.skipIf(lupa is None, "lupa not installed")
class WarpcoreFiguresTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('warpcore'))")

    def test_unlocked_tier_says_its_figures(self):
        self.assertEqual(self.M.label(P + "Button_Tier2"),
                         "Tier 2, makes 180 energy, burns 36 deuterium per cycle")

    def test_selected_tier_unchanged(self):
        self.assertEqual(self.M.label(P + "Button_Tier1"),
                         "Tier 1, selected, makes 120 energy, burns 24 deuterium per cycle")

    # Negative twins: a locked tier and Gray Mode stay as they were.
    def test_locked_tier_has_no_figures(self):
        self.assertEqual(self.M.label(P + "Button_Tier3"), "Tier 3, locked")

    def test_gray_mode_has_no_figures(self):
        self.assertEqual(self.M.label(P + "Button_GrayMode"), "Gray Mode")


if __name__ == "__main__":
    unittest.main()
