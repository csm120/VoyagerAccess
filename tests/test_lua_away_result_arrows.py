"""Arrows on an away mission task's result say the result again.

VM, 2026-11-09 (Natural Provisions, task 1): with the result up ("Success.
Skill 23, 23 needed. Neelix quickly identifies ..."), Up, Down, Left and
Right said nothing; only R repeated it. A conversation line with no choices
already answers the arrows with the line (dialogue.line_key, Casey's choice,
2026-10-26). Runs the real awaymission.lua under lupa (result_key only).
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
said = {}
package.preload["speech"] = function()
    return { say = function(t) said[#said + 1] = t end, say_long = function(t) said[#said + 1] = t end }
end
package.preload["hints"] = function() return { fresh = function() return true end } end
package.preload["screen"] = function() return { shown = function(w) return w.shown end } end
package.preload["text"] = function() return { prep = function(s) return s end } end
for _, m in ipairs({ "crumb", "keys", "popups", "tr", "dialogue", "focus" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
result_up = true
story = "Neelix quickly identifies the apples as poisonous."
local result = { shown = true }
result.DialogueTypewriterText = { TargetText = { ToString = function() return story end } }
function result:IsValid() return true end
function result:GetFullName() return "WBP_AwayMission_ChallengeResult_C /Engine/Transient.X:WBP_Dialogue_Window_AwayMission_C_1.WidgetTree_2.Result" end
outcome_up = false
local outcome = { shown = true }
function outcome:IsValid() return true end
function outcome:GetFullName() return "WBP_AwayMissionOutcome_C /Engine/Transient.X:WBP_Dialogue_Window_AwayMission_C_1.WidgetTree_2.Outcome" end
function FindAllOf(cls)
    if cls == "WBP_AwayMission_ChallengeResult_C" then result.shown = result_up return { result } end
    if cls == "WBP_AwayMissionOutcome_C" then outcome.shown = outcome_up return { outcome } end
    return {}
end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
"""

TEXT = "Success. Skill 23, 23 needed. Neelix quickly identifies the apples as poisonous."


@unittest.skipIf(lupa is None, "lupa not installed")
class AwayResultArrowTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('awaymission'))")

    def said(self):
        return list(self.lua.eval("said").values())

    def test_arrow_on_a_result_says_it_again(self):
        self.M.result_said = TEXT
        self.M.result_story = "Neelix quickly identifies the apples as poisonous."
        self.assertTrue(self.M.result_key())
        self.assertEqual(self.said()[0], TEXT)
        self.assertIn("Enter continues.", self.said())

    # Negative twins.
    def test_no_result_on_screen_leaves_the_arrow_alone(self):
        self.M.result_said = TEXT
        self.lua.execute("result_up = false")
        self.assertFalse(self.M.result_key())
        self.assertEqual(self.said(), [])

    # Fable review: the next task's panel can be up with its placeholder
    # text before its own result is read; the old result is not said.
    def test_a_newer_panel_does_not_get_the_old_result(self):
        self.M.result_said = TEXT
        self.M.result_story = "Neelix quickly identifies the apples as poisonous."
        self.lua.execute("story = 'Lorem ipsum dolor sit amet'")
        self.assertFalse(self.M.result_key())
        self.assertEqual(self.said(), [])

    # VM, 2026-11-09: the last task's result panel stays shown under the
    # mission's outcome, and the arrows (and the pause fallback) said that
    # task again. The outcome wins: its summary, as R says it.
    def test_outcome_wins_over_the_last_task(self):
        self.M.result_said = TEXT
        self.M.result_story = "Neelix quickly identifies the apples as poisonous."
        self.M.outcome_text = lambda path: "Mission complete. Rewards: 300 Food."
        self.lua.execute("outcome_up = true")
        self.assertTrue(self.M.result_key())
        self.assertEqual(self.said()[0], "Mission complete. Rewards: 300 Food.")

    # Fable review: if the outcome panel stays "shown" under the conversation
    # after the mission, the arrows must say that line, not the outcome.
    def test_outcome_left_alone_once_the_mission_is_over(self):
        self.M.outcome_text = lambda path: "Mission complete. Rewards: 300 Food."
        self.lua.execute("""
            outcome_up = true; result_up = false
            local sector = { IsValid = function() return true end,
                GetFullName = function() return "WBP_Dialogue_Window_Sector_C /Engine/Transient.X:WBP_Dialogue_Window_Sector_C_9" end }
            package.loaded['dialogue'] = { active = function() return sector end }
        """)
        self.assertFalse(self.M.result_key())
        self.assertEqual(self.said(), [])

    def test_nothing_said_yet_leaves_the_arrow_alone(self):
        self.assertFalse(self.M.result_key())
        self.assertEqual(self.said(), [])


if __name__ == "__main__":
    unittest.main()
