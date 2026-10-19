"""events.lua rounds an event option's outcome chances to fives, as the
coloured bar shows them (Casey, 2026-10-19): "26% ... 74%" became "25% ...
75%". The parts must still add up to 100, and an outcome that can happen
must never read 0%.

Runs the real Lua through lupa; skipped when lupa is not installed."""
import unittest
from pathlib import Path

try:
    import lupa
except ImportError:
    lupa = None

EVENTS = Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts" / "events.lua"


@unittest.skipIf(lupa is None, "lupa not installed")
class RoundFivesTests(unittest.TestCase):
    def setUp(self):
        lua = lupa.LuaRuntime()
        lua.execute('''
package.preload["speech"] = function() return setmetatable({}, { __index = function() return function() end end }) end
package.preload["crumb"] = function() return { at = function() end } end
''')
        self.m = lua.execute(EVENTS.read_text(encoding="utf-8"))
        self.table = lua.eval("function(...) return { ... } end")

    def rounded(self, *weights):
        r = self.m.round_fives(self.table(*weights))
        return [r[i + 1] for i in range(len(weights))]

    def test_rounds_to_fives(self):
        self.assertEqual(self.rounded(26, 74), [25, 75])

    def test_adds_up_to_100(self):
        for ws in [(1, 1, 1), (15, 47, 38), (30, 40, 25, 5), (33, 33, 34), (89, 11)]:
            r = self.rounded(*ws)
            self.assertEqual(sum(r), 100, (ws, r))
            self.assertTrue(all(x % 5 == 0 for x in r), (ws, r))

    def test_small_chance_is_not_zero(self):
        self.assertEqual(self.rounded(99, 1), [95, 5])


if __name__ == "__main__":
    unittest.main()
