"""K says one ability per key.

Casey, 2026-11-08 (his play, report at 19:56): with Telek R'Mor in slot 3, K
said "3, Cloaking Prototype, ready in 5 seconds. 3, Instant Shield Recharge,
ready in 26 seconds." The second is B'Elanna's, from a slot widget the game
left after she was swapped out; its time never moved. At 12:35 the same
happened in slot 1. Runs the real combat.lua under lupa (the choice only).
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

STUBS = r"""
local nop = setmetatable({}, { __index = function() return function() end end })
for _, m in ipairs({ "speech", "screen", "text", "tr", "keys", "popups", "events", "focus", "hints", "crumb" }) do
    package.preload[m] = function() return nop end
end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function RegisterHook() end
function NotifyOnNewObject() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay() end
function LoopAsync() end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class OnePerKeyTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('combat'))")

    def pick(self, items):
        t = self.lua.table_from([self.lua.table_from(x) for x in items])
        out = self.M.one_per_key(t)
        return [out[i]["text"] for i in range(1, len(out) + 1)]

    def test_newer_widget_wins_when_neither_is_shown(self):
        # Object numbers count down: the newer widget has the smaller one.
        self.assertEqual(self.pick([
            {"i": 2, "shown": False, "num": 2147300000, "text": "3, Instant Shield Recharge"},
            {"i": 2, "shown": False, "num": 2147290000, "text": "3, Cloaking Prototype"},
            {"i": 0, "shown": False, "num": 2147295000, "text": "1, Shield Hacking"},
        ]), ["1, Shield Hacking", "3, Cloaking Prototype"])

    def test_shown_widget_wins(self):
        self.assertEqual(self.pick([
            {"i": 0, "shown": True, "num": 2147300000, "text": "1, Cloaking Prototype"},
            {"i": 0, "shown": False, "num": 2147290000, "text": "1, Instant Shield Recharge"},
        ]), ["1, Cloaking Prototype"])

    # Negative twin: three keys, three abilities, all kept in key order.
    def test_distinct_keys_all_kept(self):
        self.assertEqual(self.pick([
            {"i": 1, "shown": False, "num": 3, "text": "2, Evasive Maneuver"},
            {"i": 0, "shown": False, "num": 2, "text": "1, Shield Hacking"},
            {"i": 2, "shown": False, "num": 1, "text": "3, Cloaking Prototype"},
        ]), ["1, Shield Hacking", "2, Evasive Maneuver", "3, Cloaking Prototype"])


if __name__ == "__main__":
    unittest.main()
