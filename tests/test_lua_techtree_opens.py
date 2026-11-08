"""A researched tier says the state of each technology it opens.

Casey heard "Tier 1, researched, opens 5: Hydroponics Bay, ..." and took the
Hydroponics Bay as researched; the build ring kept saying "Missing
technology" (his play, 2026-11-07). A sighted player sees each field's own
state on the tree. Runs the real techtree.lua under lupa.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

STUBS = r"""
package.preload["speech"] = function() return { say = function() end } end
package.preload["screen"] = function() return { shown = function() return true end } end
package.preload["tr"] = function()
    local function fill(t, ...)
        local args, i = { ... }, 0
        return (t:gsub("{[ns]}", function() i = i + 1 return tostring(args[i]) end))
    end
    return { word = function(s) return s end, fill = fill }
end
function RegisterHook() end
function FindAllOf() return {} end
function StaticFindObject() return nil end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class TierOpensTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('techtree'))")

    def techs(self, rows):
        t = self.lua.table_from([self.lua.table_from(r) for r in rows])
        return t

    def test_researched_tier_groups_by_state(self):
        names = self.techs([
            {"name": "Hydroponics Bay", "state": "available"},
            {"name": "Active-Scan Navigation", "state": "researched"},
            {"name": "Field Training", "state": "available"},
            {"name": "x", "state": "locked", "obf": True},
        ])
        self.assertEqual(self.M.opens_text(names, True),
                         ", opens 4: available: Hydroponics Bay, Field Training; "
                         "researched: Active-Scan Navigation; 1 unknown technology")

    def test_tier_not_researched_keeps_names_only(self):
        names = self.techs([
            {"name": "Science Lab Level 2", "state": "locked until its tier is researched"},
            {"name": "Waste Disassembler", "state": "locked until its tier is researched"},
        ])
        self.assertEqual(self.M.opens_text(names, False),
                         ", opens 2: Science Lab Level 2, Waste Disassembler")


if __name__ == "__main__":
    unittest.main()
