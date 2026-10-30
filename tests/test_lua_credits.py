"""credits.lua finds the credits text however deep the scroll box keeps it.

The campaign's ending had the rich text straight in CreditsScrollBox; the
Caretaker hidden ending's credits had it inside a VerticalBox, so the mod
found "no text in the scroll box", every key was silent and Backspace did
nothing: Casey was stuck on the credits (2026-10-29). Runs the real
credits.lua under lupa with the widgets stubbed.
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
package.preload["popups"] = function() return { on_widget = function() end } end
package.preload["focus"] = function() return { park_focus = function() end } end
RT = { name = "RichTextBlock" }
local function node(kind, children, text)
    local n = { kind = kind, children = children or {}, text = text }
    function n:IsValid() return true end
    function n:IsA(c) return c == RT and self.kind == "rich" end
    function n:GetChildrenCount() return #self.children end
    function n:GetChildAt(i) return self.children[i + 1] end
    function n:GetText() local t = self.text return { ToString = function() return t end } end
    return n
end
TEXT = "<H1>gameXcite</>\n\n<H2>CEO / Executive Producer</>\nPatrick Streppel\n\n<H2>Writing</>\nA\nB"
function make_credits(nested)
    local rich = node("rich", nil, TEXT)
    local box = nested and node("box", { node("vbox", { rich }) }) or node("box", { rich })
    local w = { CreditsScrollBox = box }
    function w:IsValid() return true end
    function w:IsInViewport() return true end
    function w:GetFullName() return "WBP_Credits_C /Engine/Transient.Credits_1" end
    function w:GetClass() return { GetFullName = function() return "WidgetBlueprintGeneratedClass /Game/WBP_Credits.WBP_Credits_C" end } end
    function w:DeactivateWidget() closed_by_mod = true end
    credits = w
end
function FindAllOf(c) if c == "WBP_Credits_C" then return { credits } end return {} end
function StaticFindObject(p)
    if p == "/Script/UMG.RichTextBlock" then return RT end
    if p == "/Engine/Transient.Credits_1" then return credits end
    return nil
end
function RegisterHook() end
function ExecuteInGameThread(fn) fn() end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class CreditsTextTests(unittest.TestCase):
    def run_credits(self, nested):
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        lua.execute(STUBS)
        lua.globals().make_credits(nested)
        M = lua.execute("return (require('credits'))")
        M.install()
        return lua, M, list(lua.globals().said.values())

    def test_text_straight_in_the_scroll_box(self):
        _, _, said = self.run_credits(False)
        self.assertEqual(said[0], "Credits, 3 entries. Up and Down to read, Escape to close.")

    def test_text_inside_a_vertical_box(self):
        _, _, said = self.run_credits(True)
        self.assertEqual(said[0], "Credits, 3 entries. Up and Down to read, Escape to close.")
        self.assertEqual(said[1], "gameXcite, 1 of 3")

    def test_backspace_closes_the_nested_credits(self):
        lua, M, _ = self.run_credits(True)
        self.assertTrue(M.close())
        self.assertTrue(lua.globals().closed_by_mod)


if __name__ == "__main__":
    unittest.main()
