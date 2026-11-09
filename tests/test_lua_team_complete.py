"""A filled away team slot says that Enter starts the mission once the team is complete.

VM, 2026-11-09 (game 2.2, Natural Provisions), four times in four tries:
with every slot filled, Enter on a slot (slot 3 after Up from Start Mission,
slot 3 reached from slot 2, slot 2 reached from slot 3) started the mission.
The loadout closed before the mod read the key, so the game itself took
Enter. With a slot still empty, Enter on a filled slot opened its hero list.
The slot line said "Team complete: End moves to Start Mission", which let a
player think Enter would change the hero. Runs the real awaymission.lua
under lupa (slot_label only).
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

STUBS = r"""
print = function() end
package.preload["screen"] = function() return { shown = function() return true end } end
package.preload["hints"] = function() return { fresh = function() return true end, text = function(_, t) return t end } end
package.preload["text"] = function() return { prep = function(s) return s end } end
package.preload["tr"] = function() return { lower = function(s) return s:lower() end, word = function(s) return s end } end
for _, m in ipairs({ "speech", "crumb", "keys", "popups", "dialogue", "focus", "combat" }) do
    package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
end
local function obj(t)
    t.IsValid = function() return true end
    t.GetFullName = function() return "Widget /Engine/Transient.X:Other" end
    return t
end
local function text(s) return obj({ GetText = function() return { ToString = function() return s end } end }) end
LP = "/Engine/Transient.X:WBP_AwayMissionLoadout_C_7"
names = { "Tuvok", "Chakotay", "Neelix" }
pickers = {}
for i = 1, 3 do
    local p = obj({ HeroPlaque = obj({ HeroNameText = text(""), HeroRoomText = nil }) })
    p.OpenSelectionButton = obj({})
    p.GetFullName = function() return "WBP_AwayMissionHeroPicker_C " .. LP .. ".WidgetTree_1.WBP_AwayMissionHeroPicker_C_" .. i end
    pickers[i] = p
end
function fill(n)
    for i = 1, 3 do
        local s = i <= n and names[i] or ""
        pickers[i].HeroPlaque.HeroNameText = text(s)
    end
end
local L = obj({ HeroPickers = { ForEach = function(_, fn) for i, p in ipairs(pickers) do fn(i, { get = function() return p end }) end end } })
function StaticFindObject(p) if p == LP then return L end return nil end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
"""


def slot(i):
    return f"/Engine/Transient.X:WBP_AwayMissionLoadout_C_7.WidgetTree_1.WBP_AwayMissionHeroPicker_C_{i}.WidgetTree_9.OpenSelectionButton"


@unittest.skipIf(lupa is None, "lupa not installed")
class TeamCompleteTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('awaymission'))")

    def test_full_team_slot_says_enter_starts(self):
        self.lua.execute("fill(3)")
        label = self.M.slot_label(slot(2))
        self.assertIn("Team complete. Enter starts the mission.", label)
        self.assertNotIn("End moves", label)

    # Negative twin: with a slot still empty, Enter changes the hero, and
    # nothing says it starts the mission.
    def test_team_not_full_says_nothing_of_starting(self):
        self.lua.execute("fill(2)")
        label = self.M.slot_label(slot(2))
        self.assertNotIn("starts the mission", label)
        self.assertNotIn("Team complete", label)


if __name__ == "__main__":
    unittest.main()
