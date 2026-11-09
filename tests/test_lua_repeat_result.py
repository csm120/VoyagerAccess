"""R over a battle result reads only the result.

VM, 2026-11-09: a battle ended with the order wheel open (Enter on "What are
your orders", then the enemy destroyed), and R read "Combat result: ...
HELM. ACTIONS. INITIATE REPAIRS. Surrender (Instant!) ...": the order wheel
(WBP_RadialMenu_C) was still in popups' open list under the result. Runs the
real dialogue.lua under lupa (M.repeat_windows, the window choice only).
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

STUBS = r"""
print = function() end
package.preload["tr"] = function()
    return { line = function(s) return s end, word = function(s) return s end, fill = function(s) return s end }
end
io.open = function()
    return { write = function(self) return self end, close = function() end, flush = function() end,
             seek = function() return 0 end, read = function() return nil end,
             lines = function() return function() return nil end end }
end
package.preload["screen"] = function() return { shown = function() return true end } end
package.preload["crumb"] = function() return setmetatable({}, { __index = function() return function() end end }) end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
"""

RESULT = "/Engine/Transient.X:WBP_SpaceCombat_C_1.WidgetTree_2.CombatResultView"
WHEEL = "/Engine/Transient.X:BP_STVGameInstance_C_1.WBP_RadialMenu_C_3"
AUTO = "/Engine/Transient.X:WBP_SpaceCombat_C_1.WidgetTree_2.AutoResolveWidget"
EVENT = "/Engine/Transient.X:WBP_HUD_C_1.WBP_POIMultipleChoice_C_4"
PANEL = "/Engine/Transient.X:WBP_HUD_C_1.POIDetailView"


@unittest.skipIf(lupa is None, "lupa not installed")
class RepeatWindowsTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.d = self.lua.execute("return (require('dialogue'))")

    def pick(self, *paths):
        t = self.lua.table(*paths)
        return list(self.d.repeat_windows(t).values())

    def test_result_drops_the_order_wheel_left_behind(self):
        self.assertEqual(self.pick(RESULT, WHEEL), [RESULT])

    def test_result_drops_the_auto_resolve_readout(self):
        self.assertEqual(self.pick(AUTO, RESULT), [RESULT])

    # Fable review, 2026-11-09: a tutorial over the result is still read.
    def test_result_keeps_a_tutorial_over_it(self):
        tut = "/Engine/Transient.X:BP_STVGameInstance_C_1.WBP_TutorialInfoWidget_C_5"
        self.assertEqual(self.pick(RESULT, WHEEL, tut), [RESULT, tut])

    def test_order_wheel_kept_without_a_result(self):
        self.assertEqual(self.pick(WHEEL), [WHEEL])

    def test_event_kept_alone_over_the_map_panel(self):
        self.assertEqual(self.pick(PANEL, EVENT), [EVENT])


if __name__ == "__main__":
    unittest.main()
