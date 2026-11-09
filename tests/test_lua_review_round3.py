"""GPT and Fable review fixes, 2026-11-09 (third round).

- Backspace's delayed close of a hero list: only while no other key was
  pressed, and it keeps looking while the list fades in (focus.slot_clear_step).
- The focus hush ends at the player's next key (focus.hushed): a Down inside
  the hush moved focus and the new place was never said.
- Arrows say an away result only while no other conversation is active.
- Arrows find a result whose story came from the typewriter's own text.
Runs the real focus.lua and awaymission.lua under lupa.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

FOCUS_STUBS = r"""
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

AWAY_STUBS = r"""
print = function() end
said = {}
package.preload["speech"] = function() return { say = function(t) said[#said + 1] = t end } end
package.preload["hints"] = function() return { fresh = function() return false end } end
package.preload["screen"] = function() return { shown = function(w) return w.shown end } end
package.preload["text"] = function() return { prep = function(s) return s end } end
for _, m in ipairs({ "crumb", "keys", "popups", "tr", "focus" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
active = nil
package.preload["dialogue"] = function() return { active = function() return active end } end
local function text(s) return { IsValid = function() return true end, GetText = function() return { ToString = function() return s end } end } end
result = { shown = true }
function result:IsValid() return true end
function result:GetFullName() return "WBP_AwayMission_ChallengeResult_C /Engine/Transient.X:WBP_Dialogue_Window_AwayMission_C_1.WidgetTree_2.Result" end
function FindAllOf(cls)
    if cls == "WBP_AwayMission_ChallengeResult_C" then return { result } end
    return {}
end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
function set_story(target, typed)
    result.DialogueTypewriterText = text(typed)
    result.DialogueTypewriterText.TargetText = { ToString = function() return target end }
end
function sector_active()
    active = { IsValid = function() return true end,
        GetFullName = function() return "WBP_Dialogue_Window_Sector_C /Engine/Transient.X:WBP_Dialogue_Window_Sector_C_9" end }
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class FocusRound3Tests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(FOCUS_STUBS)
        self.M = self.lua.execute("return (require('focus'))")

    def step(self, **s):
        return self.M.slot_clear_step(self.lua.table_from(s))

    def test_list_up_and_no_key_is_closed(self):
        self.assertEqual(self.step(same_key=True, list_shown=True, tries_left=3), "close")

    def test_list_fading_in_is_waited_for(self):
        self.assertEqual(self.step(same_key=True, list_shown=False, tries_left=3), "wait")

    def test_another_key_stops_it(self):
        self.assertEqual(self.step(same_key=False, list_shown=True, tries_left=3), "give_up")

    def test_no_list_after_the_tries_gives_up(self):
        self.assertEqual(self.step(same_key=True, list_shown=False, tries_left=0), "give_up")

    def test_hush_holds_until_the_next_key(self):
        self.assertTrue(self.M.hushed(10.0, 5, {"until": 11.0, "key": 5} and self.lua.table_from({"until": 11.0, "key": 5})))

    def test_hush_ends_at_the_players_key(self):
        self.assertFalse(self.M.hushed(10.0, 6, self.lua.table_from({"until": 11.0, "key": 5})))

    def test_hush_ends_in_time(self):
        self.assertFalse(self.M.hushed(12.0, 5, self.lua.table_from({"until": 11.0, "key": 5})))


@unittest.skipIf(lupa is None, "lupa not installed")
class AwayRound3Tests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(AWAY_STUBS)
        self.M = self.lua.execute("return (require('awaymission'))")

    def said(self):
        return list(self.lua.eval("said").values())

    def test_result_left_alone_under_another_conversation(self):
        self.lua.execute("set_story('The team found him.', 'The team found him.'); sector_active()")
        self.M.result_said, self.M.result_story = "Success. The team found him.", "The team found him."
        self.assertFalse(self.M.result_key())
        self.assertEqual(self.said(), [])

    def test_result_read_from_the_typed_text_is_repeated(self):
        self.lua.execute("set_story('', 'The team found him.')")
        self.M.result_said, self.M.result_story = "Success. The team found him.", "The team found him."
        self.assertTrue(self.M.result_key())
        self.assertEqual(self.said()[0], "Success. The team found him.")


if __name__ == "__main__":
    unittest.main()
