"""awaymission.lua: a task's result is said again on a later visit.

Fable review, 2026-11-10 (mod finding 5): the "already said" mark for an
away task's result was never cleared, so after loading the save from
before a task and making the same choice, the identical result was silent:
no outcome, no skill numbers, no rewards. Runs the real awaymission.lua
under lupa, through mission_poll, with the stubs of
test_lua_away_result_arrows.
"""
import unittest

from tests.test_lua_away_result_arrows import SCRIPTS, STUBS, lupa

WINDOW = r"""
away_open = true
local away = {}
function away:IsValid() return true end
function away:GetFullName() return "WBP_Dialogue_Window_AwayMission_C /Engine/Transient.X:WBP_Dialogue_Window_AwayMission_C_1" end
function away:GetClass() return { GetFName = function() return { ToString = function() return "WBP_Dialogue_Window_AwayMission_C" end } end } end
package.loaded["dialogue"] = nil
package.preload["dialogue"] = function()
    return setmetatable({ active = function() if away_open then return away end end },
        { __index = function() return function() end end })
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class AwayResultResetTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.lua.execute(WINDOW)
        self.M = self.lua.execute("return (require('awaymission'))")
        self.M.mission_active = lambda: False

    def results(self):
        return [s for s in self.lua.eval("said").values() if "apples" in s]

    def test_same_result_after_the_window_closed_is_said_again(self):
        self.M.mission_poll()
        self.assertEqual(len(self.results()), 1)
        # The away window closes (a save is loaded), then the same task's
        # result comes up again.
        self.lua.execute("away_open = false")
        self.M.mission_poll()
        self.lua.execute("away_open = true")
        self.M.mission_poll()
        self.assertEqual(len(self.results()), 2)

    def test_same_result_in_the_same_window_is_said_once(self):
        # Negative twin: polls while the result stays up do not repeat it.
        for _ in range(3):
            self.M.mission_poll()
        self.assertEqual(len(self.results()), 1)


if __name__ == "__main__":
    unittest.main()
