"""combat.lua: the new battle states reach the lines that are spoken.

GPT review, 2026-11-25: the earlier tests called the new helpers directly
and passed with the readers disconnected. These go through the readers:
the ability poll (with a hidden duplicate widget), the low-health owner
while a subsystem is repairing, and the incoming torpedo line. Runs the
real combat.lua under lupa; local readers are found through upvalues.
"""
import unittest

from tests.test_lua_combat_abilities import SCRIPTS, STUBS, lupa

MORE = r"""
package.loaded["screen"] = nil
package.preload["screen"] = function() return {
    shown = function(w) return w.visible ~= false end,
    walk = function(root, fn) for _, c in ipairs(root.children or {}) do fn(c) end end } end
function indicator(visible) return { visible = visible, IsValid = function() return true end } end
function txt(s, name)
    return { IsValid = function() return true end, IsA = function() return true end,
             GetFName = function() return { ToString = function() return name or "T" end } end,
             GetText = function() return { ToString = function() return s end } end }
end
function find_up(M, name)
    local seen = {}
    local function up(fn)
        if seen[fn] then return nil end
        seen[fn] = true
        for i = 1, 255 do
            local n, v = debug.getupvalue(fn, i)
            if n == nil then break end
            if n == name then return v end
            if type(v) == "function" then local r = up(v) if r then return r end end
        end
    end
    for _, f in pairs(M) do
        if type(f) == "function" then local r = up(f) if r then return r end end
    end
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class CombatConsumerTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS + MORE)
        self.M = self.lua.execute("return (require('combat'))")
        self.G = self.lua.globals()

    def said(self):
        return list(self.G.said.values())

    def test_poll_hidden_duplicate_does_not_flip(self):
        poll = self.lua.eval("find_up")(self.M, "abilities_poll")
        self.assertIsNotNone(poll)
        self.lua.execute("""
            shown = make(1, 'Shield Hacking', 'Harry Kim', 0, 0)
            hidden = { Index = 1, Ability = shown.Ability, visible = false,
                       IsValid = function() return true end,
                       GetFullName = function() return 'WBP_ExtAbility_C /Engine/Transient.W9' end,
                       Disabled_Indicator = indicator(false), SubsystemDisabled_Indicator = indicator(false) }
            shown.Disabled_Indicator = indicator(true)
            shown.SubsystemDisabled_Indicator = indicator(false)
            set_abilities({ shown, hidden })""")
        poll()
        poll()
        poll()
        self.assertEqual(self.said(), [])
        # Back to ready once the game clears it: said, with its key.
        self.lua.execute("shown.Disabled_Indicator = indicator(false)")
        poll()
        self.assertEqual(self.said(), ["2, Shield Hacking ready"])

    def test_poll_key_from_the_shown_widget(self):
        # GPT review, 2026-11-25: a hidden slot 1 widget listed before the
        # shown slot 2 widget of the same ability said "1, ... ready".
        poll = self.lua.eval("find_up")(self.M, "abilities_poll")
        self.lua.execute("""
            shown = make(1, 'Shield Hacking', 'Harry Kim', 3, 0)
            hidden = { Index = 0, Ability = shown.Ability, visible = false,
                       IsValid = function() return true end,
                       GetFullName = function() return 'WBP_ExtAbility_C /Engine/Transient.W9' end }
            set_abilities({ hidden, shown })""")
        poll()
        self.lua.execute("shown.Ability.CooldownLeft = 0")
        poll()
        self.assertEqual(self.said(), ["2, Shield Hacking ready"])

    def test_active_survives_a_throwing_setup_widget(self):
        # GPT review, 2026-11-25: HeroLoadout:IsValid() throwing escaped
        # M.active and stopped the battle poll.
        self.lua.execute("""
            local M = ...
            local bad = { IsValid = function() error("stale widget") end }
            for i = 1, 255 do
                local n = debug.getupvalue(M.active, i)
                if n == nil then break end
                if n == "main" then debug.setupvalue(M.active, i, function() return { HeroLoadout = bad } end) end
            end""", self.M)
        ok = self.lua.eval("function(M) local ok = pcall(M.active) return ok end")(self.M)
        self.assertIs(ok, True)

    def test_k_says_disabled_while_cooling_down(self):
        self.lua.execute("""
            a = make(0, 'Evasive Maneuver', 'Tom Paris', 12.2, 0)
            a.Disabled_Indicator = indicator(true)
            set_abilities({ a })""")
        self.assertEqual(self.M.abilities(True), "1, Evasive Maneuver, unavailable, ready in 13 seconds.")

    def test_low_shields_owner_while_repairing(self):
        self.lua.execute("""
            local function sub(name, cur, repairing)
                return { CurrentHealth = cur, MaxHealth = 100, MySubsystem = { IsValid = function() return true end },
                         SubsystemNameText = txt(name), SubsystemRepairImage = indicator(repairing) }
            end
            voyager = { IsValid = function() return true end, ShipNameText = txt('Voyager') }
            enemy = { IsValid = function() return true end, ShipNameText = txt('Kazon Raider') }
            subs = { [voyager] = { sub('Shields', 5, true) }, [enemy] = { sub('Shields', 70, false) } }""")
        ps = self.lua.eval("find_up")(self.M, "panel_subsystems")
        self.assertIsNotNone(ps)
        # The panel walk is replaced: each view's subsystems, through the
        # real subsystem_text.
        M = self.M
        self.lua.execute("""
            local M = ...
            local function replace(fn)
                for i = 1, 255 do
                    local n = debug.getupvalue(fn, i)
                    if n == nil then break end
                    if n == "panel_subsystems" then
                        debug.setupvalue(fn, i, function(view)
                            local out = {}
                            for _, x in ipairs(subs[view] or {}) do out[#out + 1] = M.subsystem_text(x) end
                            return out
                        end)
                    end
                    if n == "main" then
                        debug.setupvalue(fn, i, function() return { PlayerView = voyager, EnemyView = enemy } end)
                    end
                end
            end
            replace(M.destroyed_owner)
        """, M)
        self.assertEqual(self.M.destroyed_owner("Shields", True), "Voyager")

    def test_torpedo_line_names_the_target(self):
        inc = self.lua.eval("find_up")(self.M, "incoming_poll")
        self.assertIsNotNone(inc)
        w = self.lua.eval("""{ incomingTorpedo = true,
            Torp_Incoming = { visible = true, IsValid = function() return true end,
                              children = { txt('torpedo incoming', 'CommonTextBlock_353') } },
            IncomingTorpedoWidget = { visible = true, IsValid = function() return true end,
                TorpedoTargetText = txt('Shields'), TorpedoImpactDurationText = txt('6s') } }""")
        self.lua.execute('function StaticFindObject() return {} end')
        inc(w)
        self.assertEqual(self.said(), ["torpedo incoming, Shields, 6s"])


if __name__ == "__main__":
    unittest.main()
