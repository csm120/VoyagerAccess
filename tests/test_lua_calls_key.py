"""view.lua: H answers a lone waiting call at once.

Casey, 2026-11-27: H opened the calls list and Enter was still needed,
though he had never seen more than one call. With one call in the list, H
now clicks it; with two or more the list stays for Enter. Runs the real
view.lua under lupa with the bar and the list's buttons stubbed.
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
printed = {}
print = function(s) printed[#printed + 1] = s end
said = {}
package.preload["speech"] = function() return setmetatable({ say = function(t) said[#said + 1] = t end },
    { __index = function() return function() end end }) end
package.preload["screen"] = function() return setmetatable({ shown = function(w) return w.shown ~= false end },
    { __index = function() return function() end end }) end
package.preload["help"] = function() return setmetatable({ context = function() return "ship" end },
    { __index = function() return function() end end }) end
package.preload["tr"] = function() return setmetatable({ word = function(s) return s end },
    { __index = function() return function() end end }) end
package.preload["keys"] = function() keys_stub = { key_count = 0 }; return keys_stub end
for _, m in ipairs({ "crumb", "focus", "dialogue", "text", "hints", "popups", "ship", "calllisten" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
delayed = {}
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay(ms, fn) delayed[#delayed + 1] = fn end
function run_delayed()
    for _ = 1, 60 do
        local d = delayed
        delayed = {}
        if #d == 0 then return end
        for _, fn in ipairs(d) do fn() end
    end
end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function LoopAsync() end
journey_calls = nil  -- nil: the journey counts what the bar opens
function FindFirstOf(cls)
    if cls == "STVJourneySubsystem" then
        return { IsValid = function() return true end,
                 GetIncomingCallsNum = function() return journey_calls or calls_after_bar end }
    end
    return nil
end
-- A key pressed while the list is still coming up.
function press_key() keys_stub.key_count = keys_stub.key_count + 1 end

clicks = {}
local function button(name, on_click)
    return {
        name = name,
        IsValid = function() return true end,
        GetIsEnabled = function() return true end,
        GetFullName = function(self) return "WBP_IncomingCall_List_Button_C /Engine/Transient.GameEngine.X." .. self.name end,
        HandleButtonPressed = function() end,
        HandleButtonReleased = function() end,
        HandleButtonClicked = function(self) clicks[#clicks + 1] = self.name; if on_click then on_click() end end,
        NotificationText = { GetText = function() return { ToString = function() return name end } end },
    }
end
calls = {}
calls_after_bar = 0   -- how many calls the list gets when the bar is clicked
list_late = false     -- the list comes up a tick after the click
local function open_list()
    local function fill()
        for i = 1, calls_after_bar do calls[i] = button("Call " .. i) end
    end
    if list_late then delayed[#delayed + 1] = fill else fill() end
end
bar_button = button("IncomingCallsButton", open_list)
function FindAllOf(cls)
    if cls == "WBP_IncomingCall_List_Button_C" then return calls end
    return {}
end
local function up(fn, name)
    for i = 1, 255 do
        local n, v = debug.getupvalue(fn, i)
        if n == nil then break end
        if n == name then return i end
    end
end
function setup(M)
    local i = up(M.calls_key, "find")
    debug.setupvalue(M.calls_key, i, function(name)
        if name == "IncomingCallsButton" then return bar_button end
        return nil
    end)
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class CallsKeyTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('view'))")
        self.g = self.lua.globals()
        self.g.setup(self.M)

    def press(self, calls, late=False):
        self.g.calls_after_bar = calls
        self.g.list_late = late
        self.M.calls_key()
        self.g.run_delayed()
        return list(self.g.clicks.values()), list(self.g.said.values())

    def test_one_call_is_answered(self):
        clicks, said = self.press(1)
        self.assertEqual(clicks, ["IncomingCallsButton", "Call 1"])
        self.assertIn("Incoming call: Call 1", said)

    def test_two_calls_stay_a_list(self):
        # Negative twin: with two calls neither is clicked.
        clicks, said = self.press(2)
        self.assertEqual(clicks, ["IncomingCallsButton"])
        self.assertNotIn("Incoming call: Call 1", said)

    def test_list_up_a_tick_late_is_still_answered(self):
        clicks, _ = self.press(1, late=True)
        self.assertEqual(clicks, ["IncomingCallsButton", "Call 1"])

    # GPT and Fable reviews, 2026-11-27: a key pressed while the list is
    # still coming up (Escape opening the pause menu) stops the answer and
    # its "Incoming calls" line; one row shown while the journey counts two
    # calls is not clicked.
    def test_key_pressed_meanwhile_stops_the_answer(self):
        self.g.calls_after_bar = 1
        self.g.list_late = True
        self.M.calls_key()
        self.g.press_key()
        self.g.run_delayed()
        self.assertEqual(list(self.g.clicks.values()), ["IncomingCallsButton"])
        self.assertNotIn("Incoming calls", list(self.g.said.values()))

    def test_one_row_but_two_waiting_is_not_clicked(self):
        self.g.journey_calls = 2
        clicks, _ = self.press(1)
        self.assertEqual(clicks, ["IncomingCallsButton"])

    def test_no_list_says_what_was_pressed(self):
        clicks, said = self.press(0)
        self.assertEqual(clicks, ["IncomingCallsButton"])
        self.assertEqual(said[-1], "Incoming calls")


if __name__ == "__main__":
    unittest.main()
