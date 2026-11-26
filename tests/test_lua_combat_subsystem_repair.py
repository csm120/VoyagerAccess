"""combat.lua: a subsystem under repair says so.

WBP_SubsystemResponsive shows SubsystemRepairImage while a subsystem is
being repaired in battle; the mod said only its health (visual state
review, 2026-11-25, B2). Runs the real combat.lua under lupa.
"""
import unittest

from tests.test_lua_combat_abilities import SCRIPTS, STUBS, lupa

MORE = r"""
package.loaded["screen"] = nil
package.preload["screen"] = function() return { shown = function(w) return w.visible ~= false end } end
local function txt(s) return { IsValid = function() return true end,
    GetText = function() return { ToString = function() return s end } end } end
function subsystem(repairing)
    return { CurrentHealth = 40, MaxHealth = 100, SubsystemNameText = txt("Shields"),
             SubsystemRepairImage = { visible = repairing, IsValid = function() return true end } }
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class SubsystemRepairTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS + MORE)
        self.M = self.lua.execute("return (require('combat'))")

    def test_repairing(self):
        self.assertEqual(self.M.subsystem_text(self.lua.eval("subsystem(true)")), "Shields 40 of 100, repairing")

    def test_not_repairing(self):
        # Negative twin: the repair image hidden, health only.
        self.assertEqual(self.M.subsystem_text(self.lua.eval("subsystem(false)")), "Shields 40 of 100")


if __name__ == "__main__":
    unittest.main()
