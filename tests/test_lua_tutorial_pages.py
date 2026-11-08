"""Each tutorial frame reads only its own page.

Two tutorials opened at once after a Mess Hall upgrade ("Assign Hero" and
"Normal Food rations"). The first frame read every shown WBP_TUT_ page, so
Casey heard "Tutorial: Assign Hero", both bodies, and then the second title
alone; Enter on one left the other open in silence (2026-11-07, his own
play). The frame names its page in LastCreatedColumViewWidget (and the
Center and Character views); runs the real popups.lua under lupa.
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
package.preload["speech"] = function() return { say = function(t) said[#said + 1] = t end } end
package.preload["screen"] = function() return { shown = function(w) return w.shown ~= false end } end
package.preload["crumb"] = function() return setmetatable({}, { __index = function() return function() end end }) end
objects = {}
function widget(path, cls, fields)
    local w = fields or {}
    w.path, w.cls = path, cls
    function w:IsValid() return true end
    function w:GetFullName() return self.cls .. " " .. self.path end
    function w:GetClass()
        local c = self.cls
        return { GetFName = function() return { ToString = function() return c end } end }
    end
    objects[path] = w
    return w
end
function FindAllOf(c)
    local out = {}
    for _, w in pairs(objects) do if w.cls == c then out[#out + 1] = w end end
    table.sort(out, function(a, b) return a.path < b.path end)
    return out
end
function StaticFindObject(p) return objects[p] end
function RegisterHook() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay(_, fn) fn() end
function LoopAsync() end
"""

T = "/Engine/Transient.GameEngine_1:BP_STVGameInstance_C_1."


@unittest.skipIf(lupa is None, "lupa not installed")
class TutorialPagesTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('popups'))")
        self.widget = self.lua.globals().widget

    def paths(self, pages):
        return sorted(pages[k] for k in pages)

    def test_frame_reads_only_its_own_page(self):
        p1 = self.widget(T + "WBP_TUT_ColumnView_C_1", "WBP_TUT_ColumnView_C")
        p2 = self.widget(T + "WBP_TUT_ColumnView_C_2", "WBP_TUT_ColumnView_C")
        f1 = self.widget(T + "WBP_TutorialInfoWidget_C_1", "WBP_TutorialInfoWidget_C",
                         self.lua.table_from({"LastCreatedColumViewWidget": p1}))
        self.widget(T + "WBP_TutorialInfoWidget_C_2", "WBP_TutorialInfoWidget_C",
                    self.lua.table_from({"LastCreatedColumViewWidget": p2}))
        self.assertEqual(self.paths(self.M.tutorial_pages(f1)), [T + "WBP_TUT_ColumnView_C_1"])

    def test_hidden_own_page_is_left_out(self):
        p1 = self.widget(T + "WBP_TUT_CenterView_C_1", "WBP_TUT_CenterView_C",
                         self.lua.table_from({"shown": False}))
        f1 = self.widget(T + "WBP_TutorialInfoWidget_C_1", "WBP_TutorialInfoWidget_C",
                         self.lua.table_from({"LastCreatedCenterViewWidget": p1}))
        self.assertEqual(self.paths(self.M.tutorial_pages(f1)), [])

    def test_frame_without_links_falls_back_to_every_shown_page(self):
        self.widget(T + "WBP_TUT_ColumnView_C_1", "WBP_TUT_ColumnView_C")
        self.widget(T + "WBP_TUT_CharacterView_C_2", "WBP_TUT_CharacterView_C")
        f1 = self.widget(T + "WBP_TutorialInfoWidget_C_1", "WBP_TutorialInfoWidget_C")
        self.assertEqual(self.paths(self.M.tutorial_pages(f1)),
                         [T + "WBP_TUT_CharacterView_C_2", T + "WBP_TUT_ColumnView_C_1"])


    def frame_with_close(self, n, title):
        lua = self.lua
        f = self.widget(T + f"WBP_TutorialInfoWidget_C_{n}", "WBP_TutorialInfoWidget_C")
        lua.globals().f_ = f
        lua.globals().t_ = title
        lua.execute("""
            local f, title = f_, t_
            f.TutorialTitle = { IsValid = function() return true end,
                GetText = function() return { ToString = function() return title end } end }
            local function nop() end
            f.CloseButton = { IsValid = function() return true end, HandleButtonPressed = nop,
                HandleButtonReleased = nop, HandleButtonClicked = function() f.shown = false end }
        """)
        return f

    def test_closing_one_of_two_says_the_one_left(self):
        self.frame_with_close(1, "Tutorial: Assign Hero")
        self.frame_with_close(2, "Tutorial: Normal Food rations")
        self.assertTrue(self.M.close_tutorial())
        said = list(self.lua.globals().said.values())
        self.assertEqual(len(said), 2, said)
        self.assertIn(said[0], ("Tutorial: Assign Hero", "Tutorial: Normal Food rations"))
        self.assertEqual(said[1], "Tutorial open. Enter closes it, R repeats it.")

    def test_closing_the_last_one_says_nothing_more(self):
        self.frame_with_close(1, "Tutorial: Assign Hero")
        self.assertTrue(self.M.close_tutorial())
        self.assertEqual(list(self.lua.globals().said.values()), [])


if __name__ == "__main__":
    unittest.main()
