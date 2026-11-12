"""combat.lua: hull figures with digit grouping give the right percentage.

Fable review, 2026-11-10 (mod low 15): the hull was parsed with
(%d+)/(%d+) and no grouping removed in brief_ship, so "1,240 / 2,400"
said "hull 12000%" (240 of 2) in English, and German "1.240 / 2.400"
the same. Runs the real combat.lua under lupa with the stubs of
test_lua_combat_pause; brief_ship is reached through the module's upvalues.
"""
import unittest

from tests.test_lua_combat_pause import SCRIPTS, STUBS, lupa

EXTRA = r"""
package.loaded["tr"] = { word = function(w) return w end,
    fill = function(t, s) return (t:gsub("{s}", function() return s end)) end }
local function txt(s)
    return { IsValid = function() return true end,
             GetText = function() return { ToString = function() return s end } end }
end
function make_view(hull)
    return { IsValid = function() return true end, ShipNameText = txt("Voyager"), T_HullIntegrity = txt(hull) }
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
class HullGroupingTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.lua.execute("setmetatable(_G, nil)")
        self.lua.execute(EXTRA)
        self.M = self.lua.execute("return (require('combat'))")
        self.brief = self.lua.globals().find_local(self.M, "brief_ship")
        self.assertIsNotNone(self.brief)

    def said(self, hull):
        return self.brief(self.lua.globals().make_view(hull))

    def test_english_grouping(self):
        self.assertEqual(self.said("1,240 / 2,400"), "Voyager, hull 52%")

    def test_german_grouping(self):
        self.assertEqual(self.said("1.240 / 2.400"), "Voyager, hull 52%")

    def test_no_break_space_grouping(self):
        self.assertEqual(self.said("1 240 / 2 400"), "Voyager, hull 52%")

    def test_plain_figures(self):
        # Negative twin: the usual small hull still reads as before.
        self.assertEqual(self.said("97 / 100"), "Voyager, hull 97%")


if __name__ == "__main__":
    unittest.main()
