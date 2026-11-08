"""A Sector Map system says how many of its points are done.

Casey could not tell which systems he had already worked through: the
system's marker (WBP_SolarSystemWorldSpaceWidget) draws one icon per point
in its event state, and the mod said only "scanned" (his play, 2026-11-07).
Runs the real system.lua under lupa with the game stubbed.
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
package.preload["crumb"] = function() return setmetatable({}, { __index = function() return function() end end }) end
function RegisterHook() end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
local function arr(t)
    return { ForEach = function(_, fn) for i, v in ipairs(t) do fn(i, { get = function() return v end }) end end }
end
function poi(states)
    local p = { EventIds = arr(states) }
    function p:IsValid() return true end
    return p
end
function marker(pois) return { SystemPois = arr(pois) } end
es = { GetEventStateById = function(_, id) return id end }
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class PointsDoneTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('system'))")

    def run_marker(self, lua_pois):
        w = self.lua.execute(f"return marker({{ {lua_pois} }})")
        return self.M.points_done(w, self.lua.globals().es)

    def test_counts_finished_points(self):
        # Completed, Failed, Activatable, then an invisible point not shown.
        self.assertEqual(self.run_marker("poi({5}), poi({7, 5}), poi({3}), poi({1})"), "2 of 3 points done")

    def test_a_point_with_one_open_event_is_not_done(self):
        self.assertEqual(self.run_marker("poi({5, 4}), poi({5})"), "1 of 2 points done")

    def test_no_shown_points_says_nothing(self):
        self.assertIsNone(self.run_marker("poi({0}), poi({1})"))


if __name__ == "__main__":
    unittest.main()
