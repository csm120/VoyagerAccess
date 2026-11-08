"""Enter on a locked warp core tier says it is locked.

Casey pressed Enter on "Tier 2, locked" with a full 1500 Deuterium and heard
"Tier 2 did not engage. Deuterium 1500.", which sounded like a fuel problem
(his play, 2026-11-07). Runs the real warpcore.lua under lupa.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

STUBS = r"""
said = {}
package.preload["speech"] = function() return { say = function(t) said[#said + 1] = t end } end
cm = { selected = 1, max = 1, deut = 1500 }
function cm:IsValid() return true end
function cm:GetSelectedWarpcoreLevel() return self.selected end
function cm:GetMaxSelectableWarpcoreLevel() return self.max end
function cm:GetWarpcoreInfo() return { DeuteriumAmount = self.deut } end
function FindFirstOf(c) if c == "STVConstructionManager" then return cm end end
function ExecuteInGameThreadWithDelay(_, fn) fn() end
"""

P = "/Engine/Transient.X.WBP_MainEngineeringModule_C_1.WidgetTree_1."


@unittest.skipIf(lupa is None, "lupa not installed")
class WarpcoreLockedTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('warpcore'))")

    def said(self):
        return list(self.lua.globals().said.values())

    def test_locked_tier_says_locked(self):
        self.M.after_enter(P + "Button_Tier2")
        self.assertEqual(self.said(), ["Tier 2 is locked."])

    def test_unlocked_tier_that_did_not_run_keeps_the_deuterium(self):
        self.lua.execute("cm.selected = 0 cm.deut = 16")
        self.M.after_enter(P + "Button_Tier1")
        self.assertEqual(self.said(), ["Tier 1 did not engage. Deuterium 16."])


if __name__ == "__main__":
    unittest.main()
