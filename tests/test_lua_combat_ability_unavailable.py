"""combat.lua: an ability the game shows as unavailable is not said "ready".

The ability's state has Disabled, Charging and SubsystemDisabled besides
ready, active and cooldown (ESTVSpaceCombatExtAbilityState), drawn by
WBP_ExtAbility's Disabled_Indicator and SubsystemDisabled_Indicator. K and
the ability lines worked only from the timers, so an ability whose
subsystem was down was "ready" (visual state review, 2026-11-25, B1). Runs
the real combat.lua under lupa.
"""
import unittest

from tests.test_lua_combat_abilities import SCRIPTS, STUBS, lupa

MORE = r"""
package.loaded["screen"] = nil
package.preload["screen"] = function() return { shown = function(w) return w.visible ~= false end } end
function indicator(visible) return { visible = visible, IsValid = function() return true end } end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class AbilityUnavailableTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS + MORE)
        self.M = self.lua.execute("return (require('combat'))")
        self.lua.execute("""
            a = make(0, 'Evasive Maneuver', 'Tom Paris', 0, 0)
            b = make(1, 'Shield Hacking', 'Harry Kim', 0, 0)
            c = make(2, 'Tactical Analysis', 'Tuvok', 0, 0)
            for _, w in ipairs({ a, b, c }) do
                w.Disabled_Indicator = indicator(false)
                w.SubsystemDisabled_Indicator = indicator(false)
            end
            b.Disabled_Indicator = indicator(true)
            c.SubsystemDisabled_Indicator = indicator(true)
            set_abilities({ a, b, c })""")

    def test_k_says_unavailable(self):
        self.assertEqual(self.M.abilities(True),
                         "1, Evasive Maneuver, ready. 2, Shield Hacking, unavailable. "
                         "3, Tactical Analysis, unavailable, subsystem down.")

    def test_all_shown_ready_when_no_indicator(self):
        # Negative twin: indicators hidden, every ability ready.
        self.lua.execute("b.Disabled_Indicator = indicator(false); c.SubsystemDisabled_Indicator = indicator(false)")
        self.assertEqual(self.M.abilities(True),
                         "1, Evasive Maneuver, ready. 2, Shield Hacking, ready. 3, Tactical Analysis, ready.")


if __name__ == "__main__":
    unittest.main()
