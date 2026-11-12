"""rooms.lua: an injured hero in a room's hero list is said so in any language.

Fable review, 2026-11-10 (mod finding 6): the status over the portrait was
added only when its text contained the English letters "injur", so in the
other seven languages ("Verletzt", "Blessé", "Ранение", "負傷") an injured
hero sounded fit. The hero manager's own condition (as awaymission.lua uses
it) now decides. Runs the real rooms.lua under lupa.
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
print = function() end
package.preload["tr"] = function()
    return { line = function(s) return s end, word = function(s) return s end, fill = function(s) return s end,
             lower = function(s) return s:lower() end }
end
package.preload["screen"] = function() return { shown = function() return true end } end
package.preload["text"] = function() return { prep = function(s) return s end } end
for _, m in ipairs({ "speech", "crumb", "keys", "popups", "focus", "dialogue", "hints", "help", "ship" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
local function txt(s)
    return { IsValid = function() return true end, IsVisible = function() return true end,
             GetText = function() return { ToString = function() return s end } end }
end
status = "Verletzt"
conditions = {}
local plaque = { HeroNameText = txt("Tom Paris") }
plaque.HeroRoomText = setmetatable({}, { __index = function(_, k) return txt(status)[k] end })
button = { HeroPlaque = plaque, CurrentCharacter = { id = 7 } }
function button:IsValid() return true end
function button:GetParent() error("no list") end
local manager = { IsValid = function() return true end,
    DoesHeroHaveCondition = function(self, id, c) return conditions[c] == true end,
    GetHeroRemainingRecoveryCycles = function() return 5 end }
function FindFirstOf(cls) if cls == "STVHeroManager" then return manager end end
function FindAllOf() return {} end
function StaticFindObject() return button end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
function no_texts(M)
    for i = 1, 255 do
        local n = debug.getupvalue(M.hero_label, i)
        if n == nil then break end
        if n == "texts_under" then debug.setupvalue(M.hero_label, i, function() return {} end) end
    end
end
"""

PATH = "/Engine/Transient.X:WBP_RoomWindow_C_1.WidgetTree_1.WBP_RoomHeroSelectionButton_C_2"


@unittest.skipIf(lupa is None, "lupa not installed")
class RoomHeroInjuredTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('rooms'))")
        self.M.skills_of = lambda sheet: ""
        self.lua.globals().no_texts(self.M)

    def test_german_injured_hero_is_said_injured(self):
        self.lua.execute("conditions[3] = true")
        self.assertTrue(self.M.hero_label(PATH).startswith("Tom Paris, verletzt"), self.M.hero_label(PATH))

    def test_room_name_in_the_field_is_not_said(self):
        # Negative twin: a fit hero's field (a room name) is still left out.
        self.lua.execute('status = "Krankenstation"')
        self.assertEqual(self.M.hero_label(PATH), "Tom Paris.")


if __name__ == "__main__":
    unittest.main()
