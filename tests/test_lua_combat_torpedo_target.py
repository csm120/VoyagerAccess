"""combat.lua: "torpedo incoming" names the subsystem it targets.

The game's IncomingTorpedoWidget (USTVTorpedoWidget: TorpedoTargetText,
TorpedoImpactDurationText) shows which subsystem an enemy torpedo targets
and its time to impact; the mod said only "torpedo incoming" (unheard
readers check, 2026-11-25). Runs the real combat.lua under lupa.
"""
import unittest

from tests.test_lua_combat_abilities import SCRIPTS, STUBS, lupa

MORE = r"""
package.loaded["screen"] = nil
package.preload["screen"] = function() return { shown = function(w) return w.visible ~= false end } end
local function txt(s, visible)
    return { visible = visible, IsValid = function() return true end,
             GetText = function() return { ToString = function() return s end } end }
end
function torpedo(visible, target, time)
    return { visible = visible, IsValid = function() return true end,
             TorpedoTargetText = txt(target, true), TorpedoImpactDurationText = txt(time, true) }
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class TorpedoTargetTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS + MORE)
        self.M = self.lua.execute("return (require('combat'))")

    def test_target_and_time_when_shown(self):
        w = self.lua.eval("{ IncomingTorpedoWidget = torpedo(true, 'Shields', '6s') }")
        self.assertEqual(self.M.torpedo_details(w), "Shields, 6s")

    def test_nothing_when_the_panel_is_hidden(self):
        # Negative twin: the panel is not on screen, so nothing is added.
        w = self.lua.eval("{ IncomingTorpedoWidget = torpedo(false, 'Shields', '6s') }")
        self.assertIsNone(self.M.torpedo_details(w))


if __name__ == "__main__":
    unittest.main()
