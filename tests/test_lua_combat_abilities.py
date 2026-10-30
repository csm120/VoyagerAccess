"""combat.lua's K readout and ability lines: each ability with its key.

I twice was too long to listen through for the ability keys, and arrows in
battle are the game's energy keys, which end a pause, so K says only the
abilities with their keys; an ability turning ready says its key too
(Casey, 2026-10-29). Runs the real combat.lua under lupa with the game's
widgets stubbed.
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
handlers = {}
package.preload["speech"] = function() return { say = function(t, i) said[#said + 1] = t end } end
package.preload["screen"] = function() return { shown = function() return true end } end
package.preload["text"] = function() return { prep = function(s) return s end, title = function(s) return s end } end
package.preload["tr"] = function() return { word = function(w) return w end,
    fill = function(t, n) return (t:gsub("{n}", tostring(n))) end } end
package.preload["events"] = function() return { hero_name = function(id) return id end } end
package.preload["keys"] = function() return { on = function(k, fn) handlers[k] = fn end } end
package.preload["popups"] = function() return setmetatable({}, { __index = function() return function() end end }) end
local function fstr(s) return { ToString = function() return s end } end
local function ability(index, name, hero, cooldown, active)
    local ab = { AbilityName = fstr(name), HeroID = fstr(hero), CooldownLeft = cooldown, ActiveTimeLeft = active }
    function ab:IsValid() return true end
    function ab:GetFullName() return "Ability /Engine/Transient.Ab" .. index end
    local w = { Index = index, Ability = ab }
    function w:IsValid() return true end
    function w:GetFullName() return "WBP_ExtAbility_C /Engine/Transient.W" .. index end
    return w
end
widgets = {}
function set_abilities(list) widgets = list end
function FindAllOf(cls) if cls == "WBP_ExtAbility_C" then return widgets end return {} end
function StaticFindObject() return nil end
function RegisterHook() end
function ExecuteWithDelay() end
function LoopAsync() end
make = ability
-- Any other UE4SS global install() calls (hooks, loops) does nothing here.
setmetatable(_G, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() end end
end })
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class AbilityKeyTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('combat'))")
        self.lua.execute("""set_abilities({ make(0, 'Evasive Maneuver', 'Tom Paris', 0, 0),
            make(1, 'Shield Hacking', 'Harry Kim', 12.2, 0), make(2, 'Tactical Analysis', 'Tuvok', 0, 0) })""")

    def said(self):
        return list(self.lua.globals().said.values())

    def test_short_line_has_keys_and_states_without_heroes(self):
        self.assertEqual(self.M.abilities(True),
                         "1, Evasive Maneuver, ready. 2, Shield Hacking, ready in 13 seconds. 3, Tactical Analysis, ready.")

    def test_full_line_unchanged_for_i_twice(self):
        self.assertEqual(self.M.abilities(),
                         "Abilities: 1, Evasive Maneuver, Tom Paris, ready; 2, Shield Hacking, Harry Kim, "
                         "ready in 13 seconds; 3, Tactical Analysis, Tuvok, ready")

    def test_k_in_battle_says_the_short_line(self):
        self.M.active = lambda: True
        self.M.say_abilities()
        self.assertEqual(self.said(), [self.M.abilities(True)])

    def test_k_outside_battle_says_so(self):
        self.M.active = lambda: False
        self.M.say_abilities()
        self.assertEqual(self.said(), ["Abilities are read in battle."])

    def test_k_with_no_abilities(self):
        self.M.active = lambda: True
        self.lua.execute("set_abilities({})")
        self.M.say_abilities()
        self.assertEqual(self.said(), ["No abilities in this battle."])

    def test_install_binds_k(self):
        self.M.install()
        self.assertIsNotNone(self.lua.globals().handlers["k"])


if __name__ == "__main__":
    unittest.main()
