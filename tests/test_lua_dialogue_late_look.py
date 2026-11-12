"""dialogue.lua: a delayed speaker look never says a line that was replaced.

Fable review, 2026-11-10 (mod finding 10): a line whose speaker field was
still the placeholder was said by a look up to 1.2 s later. If the player
pressed Enter in that time, line 2 was said, and then the pending look said
"Tuvok: line 1" after it. Runs the real dialogue.lua under lupa; say_line
is reached through the module's upvalues.
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
print = function() end
said = {}
delayed = {}
package.preload["tr"] = function()
    return { line = function(s) return s end, word = function(s) return s end, fill = function(s) return s end }
end
package.preload["speech"] = function()
    local function add(t) said[#said + 1] = t end
    return setmetatable({ say = add, say_story = add, say_long = add },
        { __index = function() return function() end end })
end
package.preload["text"] = function() return { prep = function(s) return s end } end
package.preload["screen"] = function() return { shown = function(o) return o.shown end } end
package.preload["crumb"] = function() return setmetatable({}, { __index = function() return function() end end }) end
field = { shown = false, visible = false, text = "Character Name" }
function field:IsValid() return true end
function field:IsVisible() return self.visible end
function field:GetText() local t = self.text return { ToString = function() return t end } end
win = { shown = true, DialogueSpeakerText = field }
function win:IsValid() return true end
function win:GetFullName() return "WBP_Dialogue_Window_C /Engine/Transient.X:WBP_Dialogue_Window_C_1" end
function win:GetClass() return { GetFName = function() return { ToString = function() return "WBP_Dialogue_Window_C" end } end } end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return win end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay(ms, fn) delayed[#delayed + 1] = fn end
function LoopAsync() end
function run_delayed()
    for _ = 1, 20 do
        local d = delayed
        delayed = {}
        if #d == 0 then return end
        for _, fn in ipairs(d) do fn() end
    end
end
local function up(fn, name, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 255 do
        local n, v = debug.getupvalue(fn, i)
        if n == nil then break end
        if n == name then return v end
        if type(v) == "function" then
            local a = up(v, name, seen)
            if a then return a end
        end
    end
end
function find_local(M, name)
    for _, f in pairs(M) do
        if type(f) == "function" then
            local v = up(f, name)
            if v then return v end
        end
    end
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class LateLookTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('dialogue'))")
        self.g = self.lua.globals()
        self.say_line = self.g.find_local(self.M, "say_line")
        self.assertIsNotNone(self.say_line)

    def said(self):
        return list(self.g.said.values())

    def name_shows(self):
        self.lua.execute('field.shown = true; field.visible = true; field.text = "Tuvok"')

    def test_replaced_line_is_not_said_late(self):
        self.say_line(self.g.win, "Character Name", "Repairs in progress.")
        self.assertEqual(self.said(), [])          # waiting for the name
        self.name_shows()
        self.say_line(self.g.win, "Tuvok", "Until completion, it would be logical to wait.")
        self.g.run_delayed()
        self.assertEqual(self.said(), ["Tuvok: Until completion, it would be logical to wait."])

    def test_late_name_still_said_with_its_line(self):
        # Negative twin: no newer line, so the look says the line with its name.
        self.say_line(self.g.win, "Character Name", "Repairs in progress.")
        self.name_shows()
        self.g.run_delayed()
        self.assertEqual(self.said(), ["Tuvok: Repairs in progress."])


if __name__ == "__main__":
    unittest.main()
