"""dialogue.lua: a continue dropped by a long frame is sent again, safely.

IA_Dialogue_Continue is a Tap (0.3 s). Casey's play, 2026-11-27: the
Enters the game ignored had a 0.38 s frame right after the injected press.
The mod sends it again 120 ms later, at most twice, and only while nothing
has moved on (GPT and Fable reviews, 2026-11-27): same line, still
finished, no key pressed since, and the frame measured is the one right
after the press. Runs the real dialogue.lua under lupa; injections are
counted from the mod's own "continue" log line (no input action stubbed).
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
printed = {}
print = function(s) printed[#printed + 1] = s end
package.preload["speech"] = function() return setmetatable({ said_since = function() return false end },
    { __index = function() return function() end end }) end
package.preload["keys"] = function() keys_stub = { key_count = 0 }; return keys_stub end
package.preload["focus"] = function() return setmetatable({ current_path = function() return nil end },
    { __index = function() return function() end end }) end
package.preload["awaymission"] = function() return setmetatable({ mission_active = function() return false end },
    { __index = function() return function() end end }) end
package.preload["popups"] = function() return setmetatable({ open_windows = function() return {} end },
    { __index = function() return function() end end }) end
for _, m in ipairs({ "crumb", "screen", "text", "tr", "hints", "help", "story" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
os.clock = function() return 100 end

frame = 1000
frame_dt = 0.033
delayed = {}   -- { ms, fn }
next_tick = {}
function ExecuteInGameThread(fn) next_tick[#next_tick + 1] = fn end
function ExecuteInGameThreadWithDelay(ms, fn) delayed[#delayed + 1] = { ms = ms, fn = fn } end
function tick()
    frame = frame + 1
    local t = next_tick
    next_tick = {}
    for _, fn in ipairs(t) do fn() end
end
-- Runs the retry timers (not the 3 s held-line check).
function run_retaps(ms)
    local d = delayed
    delayed = {}
    for _, e in ipairs(d) do
        if e.ms == ms then e.fn() else delayed[#delayed + 1] = e end
    end
end
local KSL = { GetFrameCount = function() return frame end }
local GS = { GetWorldDeltaSeconds = function() return frame_dt end }
function StaticFindObject(p)
    if p:find("KismetSystemLibrary", 1, true) then return KSL end
    if p:find("GameplayStatics", 1, true) then return GS end
    return nil
end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function LoopAsync() end

local function text(s) return { GetText = function() return { ToString = function() return s end } end } end
win = {
    IsValid = function() return true end,
    bLineFinished = true,
    DialogueSpeakerText = text("Neelix"),
    DialogueText = setmetatable({ IsValid = function() return true end, HasFinishedPlayingLine = function() return true end },
        { __index = function(_, k) if k == "GetText" then return function() return { ToString = function() return line_words end } end end end }),
}
line_words = "No..."
function injections()
    local n = 0
    for _, s in ipairs(printed) do if s:find("dialogue: continue action not found", 1, true) then n = n + 1 end end
    return n
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class ContinueRetryTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('dialogue'))")
        self.g = self.lua.globals()
        self.lua.execute("local M = require('dialogue'); M.active = function() return win end")
        self.ms = self.M.RETAP_MS

    def press(self):
        self.lua.execute("require('dialogue').continue()")

    def test_long_frame_sends_it_again_once_the_press_let_go(self):
        self.g.frame_dt = 0.38
        self.press()
        self.lua.execute("tick()")
        self.assertEqual(self.g.injections(), 1)
        self.lua.execute("frame_dt = 0.033")
        self.lua.execute(f"run_retaps({self.ms})")
        self.assertEqual(self.g.injections(), 2)

    def test_at_most_two_more(self):
        self.g.frame_dt = 0.38
        self.press()
        for _ in range(5):
            self.lua.execute(f"tick(); run_retaps({self.ms})")
        self.assertEqual(self.g.injections(), 3)

    # Negative twins.
    def test_normal_frame_is_not_sent_again(self):
        self.press()
        self.lua.execute(f"tick(); run_retaps({self.ms})")
        self.assertEqual(self.g.injections(), 1)

    def test_line_moved_on_is_not_sent_again(self):
        self.g.frame_dt = 0.38
        self.press()
        self.lua.execute("tick()")
        self.lua.execute("line_words = 'So... I am dying?'")
        self.lua.execute(f"run_retaps({self.ms})")
        self.assertEqual(self.g.injections(), 1)

    def test_key_pressed_meanwhile_is_not_sent_again(self):
        self.g.frame_dt = 0.38
        self.press()
        self.lua.execute("tick(); keys_stub.key_count = keys_stub.key_count + 1")
        self.lua.execute(f"run_retaps({self.ms})")
        self.assertEqual(self.g.injections(), 1)

    def test_line_no_longer_finished_is_not_sent_again(self):
        self.g.frame_dt = 0.38
        self.press()
        self.lua.execute("tick(); win.bLineFinished = false")
        self.lua.execute(f"run_retaps({self.ms})")
        self.assertEqual(self.g.injections(), 1)

    def test_long_frame_measured_late_is_not_trusted(self):
        # The check ran two frames after the press: its frame time may be a
        # hitch from a continue the game took.
        self.g.frame_dt = 0.38
        self.press()
        self.lua.execute("frame = frame + 1; tick()")
        self.lua.execute(f"run_retaps({self.ms})")
        self.assertEqual(self.g.injections(), 1)


if __name__ == "__main__":
    unittest.main()
