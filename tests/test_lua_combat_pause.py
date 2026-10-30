"""combat.lua: "Combat resumed" when the game's pause event says it runs.

Closing a combat tutorial ran the battle again while the pause text still
showed for the one OnCombatPauseChanged that came, so the mod never said
"Combat resumed" (Casey's battles, 2026-10-29, three times). The event's
own bPaused is now trusted. Runs the real combat.lua under lupa; the hook
is driven as the game calls it.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

STUBS = r"""
said = {}
hooks = {}
delayed = {}
T = 0
os.clock = function() return T end
package.preload["speech"] = function() return { say = function(t) said[#said + 1] = t end } end
package.preload["screen"] = function() return { shown = function() return true end } end
package.preload["text"] = function() return { prep = function(s) return s end, title = function(s) return s end } end
package.preload["tr"] = function() return { word = function(w) return w end, fill = function(t) return t end } end
package.preload["keys"] = function() return { on = function() end } end
package.preload["popups"] = function() return { on_widget = function() end, open_of = function() return false end } end
setmetatable(_G, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() end end
end })
function RegisterHook(name, fn) hooks[name] = fn return 1, 2 end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay(ms, fn) delayed[#delayed + 1] = fn end
WIDGET = {}
function WIDGET:IsValid() return true end
function WIDGET:GetClass() return { GetFullName = function() return "WidgetBlueprintGeneratedClass /Game/WBP_CombatMainWidget.WBP_CombatMainWidget_C" end } end
local function find_upvalue(fn, name, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 255 do
        local n, v = debug.getupvalue(fn, i)
        if n == nil then break end
        if n == name then return v, fn, i end
        if type(v) == "function" then
            local a, b, c = find_upvalue(v, name, seen)
            if a then return a, b, c end
        end
    end
end
function setup(M)
    local ensure = find_upvalue(M.install, "ensure_pause_hook")
    if not ensure then
        for _, f in pairs(M) do
            if type(f) == "function" then ensure = find_upvalue(f, "ensure_pause_hook") end
            if ensure then break end
        end
    end
    for i = 1, 255 do
        local n = debug.getupvalue(ensure, i)
        if n == nil then break end
        if n == "main" then debug.setupvalue(ensure, i, function() return WIDGET end) end
    end
    -- pause_poll's own main() too (its delayed look calls it).
    local poll = find_upvalue(ensure, "pause_poll")
    for i = 1, 255 do
        local n = debug.getupvalue(poll, i)
        if n == nil then break end
        if n == "main" then debug.setupvalue(poll, i, function() return WIDGET end) end
    end
    ensure()
end
function pause_event(paused)
    for name, fn in pairs(hooks) do
        if name:find(":OnCombatPauseChanged", 1, true) then
            fn({}, { get = function() return paused end }, { get = function() return 0 end })
        end
    end
end
function run_delayed()
    local d = delayed
    delayed = {}
    for _, fn in ipairs(d) do fn() end
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class PauseEventTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('combat'))")
        self.M.active = lambda: True
        self.text = "Combat is paused"
        self.M.paused_text = lambda w: self.text
        self.lua.globals().setup(self.M)
        self.g = self.lua.globals()

    def said(self):
        return list(self.g.said.values())

    def test_resumed_while_the_pause_text_still_shows(self):
        self.g.pause_event(True)
        self.assertEqual(self.said(), ["Combat is paused"])
        # The tutorial closes: the event says the battle runs, the text has
        # not hidden yet, and no later event comes.
        self.g.pause_event(False)
        self.g.T = 0.5
        self.g.run_delayed()
        self.assertEqual(self.said(), ["Combat is paused", "Combat resumed"])

    def test_paused_event_with_the_text_says_paused_once(self):
        self.g.pause_event(True)
        self.g.pause_event(True)
        self.assertEqual(self.said(), ["Combat is paused"])

    def test_text_gone_still_says_resumed(self):
        # The case that worked before: the text hid by the event.
        self.g.pause_event(True)
        self.text = None
        self.g.pause_event(False)
        self.g.T = 0.5
        self.g.run_delayed()
        self.assertEqual(self.said(), ["Combat is paused", "Combat resumed"])


if __name__ == "__main__":
    unittest.main()
