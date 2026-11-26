"""system.lua: a course the game refuses says the game's own reason.

Casey's play, 2026-11-25: Set course to a system the story has not opened
showed the red toast "You cannot travel here: Progress main story to
unlock". The mod queued it once, the menu line cut it off, and the game
reused the same toast after that, so later tries were silent.
refusal_text reads the shown error toast for the course's own check.
Runs the real system.lua under lupa.
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
for _, m in ipairs({ "speech", "crumb", "keys", "focus", "help", "tr", "hints", "popups", "combat", "events", "ship" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
package.preload["text"] = function() return { prep = function(s) return s end, has_words = function(s) return s:find("%a") ~= nil end } end
package.preload["screen"] = function() return { shown = function(w) return w.visible ~= false end } end
local function txt(s) return { IsValid = function() return true end,
    GetText = function() return { ToString = function() return s end } end } end
toasts = {}
function toast(s, visible)
    return { visible = visible, IsValid = function() return true end, RichText = txt(s) }
end
function FindAllOf(cls) if cls == "WBP_Toast_Error_C" then return toasts end return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class CourseRefusalTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('system'))")

    def test_shown_error_toast_is_the_reason(self):
        self.lua.execute("toasts = { toast('You cannot travel here: <b>Progress main story to unlock</>', true) }")
        self.assertEqual(self.M.refusal_text(), "You cannot travel here: Progress main story to unlock")

    def test_reason_not_repeated_right_after_the_toast(self):
        # VM, 2026-11-25: the toast reader said it, then the course check said
        # it again. Said again only when something else came after it (in
        # Casey's game the menu line had cut it off).
        self.lua.execute("""
            said = {}
            package.loaded["speech"] = { recent = {}, say = function(t) said[#said + 1] = t end }""")
        why = "You cannot travel here: Progress main story to unlock"
        self.lua.execute(f'package.loaded["speech"].recent = {{ {{ text = "Set course, 2 of 2", at = os.clock() }}, {{ text = "{why}", at = os.clock() }} }}')
        self.M.say_refusal(why)
        self.assertEqual(list(self.lua.globals().said.values()), [])
        self.lua.execute(f'package.loaded["speech"].recent = {{ {{ text = "{why}", at = os.clock() }}, {{ text = "Set course, 2 of 2", at = os.clock() }} }}')
        self.M.say_refusal(why)
        self.assertEqual(list(self.lua.globals().said.values()), [why])

    def test_second_try_long_after_is_said(self):
        # Fable review, 2026-11-25: Shift+Enter twice on a locked system, the
        # reason the last line from the first try: the second was silent.
        self.lua.execute("""
            said = {}
            package.loaded["speech"] = { recent = {}, say = function(t) said[#said + 1] = t end }""")
        why = "You cannot travel here: Progress main story to unlock"
        self.lua.execute(f'package.loaded["speech"].recent = {{ {{ text = "{why}", at = os.clock() - 30 }} }}')
        self.M.say_refusal(why)
        self.assertEqual(list(self.lua.globals().said.values()), [why])

    def test_stale_toast_is_not_this_courses_reason(self):
        # Fable review: a toast already up before the hold, from another
        # point, is not the reason a new course was not taken (no toast
        # events counted: the text rule).
        self.lua.execute("toasts = { toast('You cannot travel here: Progress main story to unlock', true) }")
        why = "You cannot travel here: Progress main story to unlock"
        self.assertIsNone(self.M.refusal_for("/point/A", why, 0))
        # A toast that was not up before the hold is the reason.
        self.assertEqual(self.M.refusal_for("/point/A", None, 0), why)
        # And the same point refused again keeps its reason.
        self.assertEqual(self.M.refusal_for("/point/A", why, 0), why)

    def test_reused_toast_shown_again_for_another_point(self):
        # GPT review, 2026-11-25: two locked points, the same message, the
        # game's one toast reused. The toast's own show event during this
        # hold makes it this course's reason.
        self.lua.execute("""
            toasts = { toast('You cannot travel here: Progress main story to unlock', true) }
            package.loaded["popups"] = { error_toast_seq = 5 }""")
        why = "You cannot travel here: Progress main story to unlock"
        self.assertEqual(self.M.refusal_for("/point/A", why, 4), why)
        self.assertEqual(self.M.refusal_for("/point/B", why, 4), why)
        # Not shown during this hold: an old toast, not the reason.
        self.assertIsNone(self.M.refusal_for("/point/C", why, 5))
        # No toast up before the hold and one up after, the count unmoved
        # (shown another way; Fable check, 2026-11-25): still the reason.
        self.assertEqual(self.M.refusal_for("/point/D", None, 5), why)

    def test_no_toast_no_reason(self):
        # Negative twin: a hidden toast (an old one) is not the reason.
        self.lua.execute("toasts = { toast('You cannot travel here: Progress main story to unlock', false) }")
        self.assertIsNone(self.M.refusal_text())


if __name__ == "__main__":
    unittest.main()
