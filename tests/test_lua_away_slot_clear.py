"""Backspace on a filled away team slot empties it.

Casey, 2026-11-09: once every slot is filled the game starts the mission on
Enter on any slot (game 2.2), so a hero could not be changed. VM, 2026-11-09:
a click on a full team's slot still opens its hero list, and Backspace in that
list empties the slot; with a slot empty, Enter is safe again. Casey: "if
backspace does it just keep it that way". Runs the real focus.lua under lupa
(slot_clear_ok, which slots Backspace empties; the click and close are
checked by hearing).
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

STUBS = r"""
local nop = setmetatable({}, { __index = function() return function() end end })
for _, m in ipairs({ "speech", "screen", "crumb", "keys", "popups", "ship", "construction", "text", "hints", "tr" }) do
    package.preload[m] = function() return nop end
end
package.preload["popups"] = function()
    return setmetatable({ SAVE_WARNINGS = {}, ROOM_WARNINGS = {} }, { __index = function() return function() end end })
end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
"""

AWAY = "/Engine/Transient.X:WBP_AwayMissionLoadout_C_7.WidgetTree_1.HeroPlaqueLayout.WBP_AwayMissionHeroPicker_C_2.WidgetTree_9.OpenSelectionButton"
COMBAT = "/Engine/Transient.X:WBP_CombatHeroLoadout_C_3.WidgetTree_1.WBP_AwayMissionHeroPicker_C_2.WidgetTree_9.OpenSelectionButton"


@unittest.skipIf(lupa is None, "lupa not installed")
class AwaySlotClearTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('focus'))")

    def test_filled_away_slot_is_cleared(self):
        self.assertEqual(self.M.slot_clear_hero(AWAY, "Away team slot 2 of 3: Tom Paris, level 4, Pilot. Team complete. Enter starts the mission."), "Tom Paris")

    # Negative twins.
    def test_empty_slot_is_left_alone(self):
        self.assertIsNone(self.M.slot_clear_hero(AWAY, "Away team slot 2 of 3, empty."))

    def test_battle_slot_is_left_alone(self):
        self.assertIsNone(self.M.slot_clear_hero(COMBAT, "Combat slot 2 of 3: Tom Paris, rank 2."))

    def test_not_a_slot(self):
        self.assertIsNone(self.M.slot_clear_hero("/Engine/Transient.X:WBP_PauseMenu_C_1.ResumeButton", "RESUME, 1 of 5"))


if __name__ == "__main__":
    unittest.main()
