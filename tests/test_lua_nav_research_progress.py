"""view.lua: the N list's Research item says the navigation bar's progress.

Casey, 2026-11-25: research was running and he did not know. A sighted
player sees the Research button's bar fill (and its paused look); the N list
said only "Research". research_progress reads the button's four bars
(research and analysis, active and paused) the way the screen shows them.
Runs the real view.lua under lupa with the widgets faked.
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
for _, m in ipairs({ "speech", "crumb", "keys", "focus", "help", "tr", "text", "hints", "ship", "popups" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
package.preload["screen"] = function() return { shown = function(w) return w.visible end } end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
local function w(visible, pct)
    return { visible = visible, Percent = pct or 0, IsValid = function() return true end }
end
function button(spec)
    local b = { IsValid = function() return true end }
    for _, k in ipairs({ "Border_inProgress", "ResearchBar_active", "Border_paused", "ResearchBar_paused",
        "AnalysisBorder_inProgress", "AnalysisBar_active", "AnalysisBorder_paused", "AnalysisBar_paused" }) do
        b[k] = w(false)
    end
    for k, v in pairs(spec) do b[k] = w(true, v) end
    return b
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class NavResearchProgressTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('view'))")

    def words(self, spec):
        t = self.lua.table_from(spec)
        return self.M.research_progress(self.lua.globals().button(t))

    def test_research_running(self):
        self.assertEqual(self.words({"Border_inProgress": 0.4, "ResearchBar_active": 0.404}),
                         "in progress, 40%")

    def test_research_paused(self):
        self.assertEqual(self.words({"Border_paused": 0, "ResearchBar_paused": 0.25}), "paused, 25%")

    def test_research_and_analysis(self):
        self.assertEqual(self.words({"Border_inProgress": 0, "ResearchBar_active": 0.5,
                                     "AnalysisBorder_paused": 0, "AnalysisBar_paused": 0.1}),
                         "in progress, 50%, analysis paused, 10%")

    def test_bar_inside_hidden_border_is_not_said(self):
        # The bar alone counts as shown, but its border is hidden: nothing
        # is on screen, so nothing is said.
        self.assertIsNone(self.words({"ResearchBar_active": 0.5}))

    def test_the_n_list_line_says_it(self):
        # Through nav_text, the line the N list speaks (GPT review,
        # 2026-11-25: the helper alone passed with the list disconnected).
        self.lua.execute("""
            local M = ...
            package.loaded["tr"] = { word = function(w) return w end }
            bar = { IsValid = function() return true end,
                    ResearchButton = button({ Border_inProgress = 0, ResearchBar_active = 0.4 }) }
            for _, f in pairs(M) do
                if type(f) == "function" then
                    for i = 1, 255 do
                        local n, v = debug.getupvalue(f, i)
                        if n == nil then break end
                        if n == "nav_text" then nav_text_fn = v end
                    end
                end
            end
            for i = 1, 255 do
                local n = debug.getupvalue(nav_text_fn, i)
                if n == nil then break end
                if n == "nav_bar" then debug.setupvalue(nav_text_fn, i, function() return bar end) end
            end
        """, self.M)
        line = self.lua.eval('nav_text_fn({ "Research", "ResearchButton" })')
        self.assertEqual(line, "Research, in progress, 40%")

    def test_n_then_down_to_research(self):
        # Through the N list's own keys (GPT review, 2026-11-25): N opens
        # the list and Down reaches Research with its progress.
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        lua.execute(STUBS.replace('"speech", ', '').replace('"help", ', '').replace('"tr", ', ''))
        lua.execute("""
            said = {}
            package.preload["speech"] = function() return setmetatable({ say = function(t) said[#said + 1] = t end },
                { __index = function() return function() end end }) end
            package.preload["help"] = function() return setmetatable({ context = function() return "ship" end },
                { __index = function() return function() end end }) end
            package.preload["tr"] = function() return { word = function(w) return w end } end""")
        M = lua.execute("return (require('view'))")
        lua.execute("""
            local M = ...
            local function btn(extra)
                local b = extra or {}
                b.visible = true
                b.IsValid = function() return true end
                b.GetIsEnabled = function() return true end
                return b
            end
            bar = { IsValid = function() return true end }
            for _, n in ipairs({ "ShowShipButton", "ShowSystemButton", "ShowSectorButton", "OverviewButton",
                                 "WaitOneCycleButton", "TutorialButton" }) do bar[n] = btn() end
            bar.ResearchButton = button({ Border_paused = 0, ResearchBar_paused = 0.6 })
            bar.ResearchButton.GetIsEnabled = function() return true end
            bar.ResearchButton.visible = true
            local seen = {}
            local function set(f)
                if seen[f] then return end
                seen[f] = true
                for i = 1, 255 do
                    local n, v = debug.getupvalue(f, i)
                    if n == nil then break end
                    if n == "bar_path" then debug.setupvalue(f, i, "bar") end
                    if type(v) == "function" then set(v) end
                end
            end
            for _, f in pairs(M) do if type(f) == "function" then set(f) end end
            StaticFindObject = function(p) if p == "bar" then return bar end end""", M)
        M.nav_toggle()
        for _ in range(4):
            M.nav_step(1)
        # No tutorial button in this stand-in, so six items.
        self.assertEqual(list(lua.globals().said.values())[-1], "Research, paused, 60%, 5 of 6")

    def test_nothing_running(self):
        # Negative twin: no bar shown, the item stays "Research".
        self.assertIsNone(self.words({}))


if __name__ == "__main__":
    unittest.main()
