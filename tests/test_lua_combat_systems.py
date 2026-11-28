"""Battle systems said as they change.

Casey, 2026-11-27 (he chose 1 and 2): in battle, after picking an enemy
system on the order wheel nothing more was said about it, and Voyager's own
systems going out were silent; a sighted player watches those bars.
1. The targeted enemy system: at half health, when it is knocked out, and
   when it works again.
2. Voyager's systems: when one is knocked out and when it works again.
Runs the real combat.lua under lupa (the decision only).
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

ENABLED = 3


@unittest.skipIf(lupa is None, "lupa not installed")
class SystemEventTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('combat'))")

    def event(self, prev, cur, half):
        p = self.lua.table_from(prev) if prev is not None else None
        return self.M.system_event(p, self.lua.table_from(cur), half)

    def test_knocked_out_when_health_reaches_zero(self):
        self.assertEqual(self.event({"hp": 12, "max": 30}, {"hp": 0, "max": 30, "status": 1}, False), "out")

    def test_half_only_for_the_target(self):
        self.assertEqual(self.event({"hp": 16, "max": 30}, {"hp": 14, "max": 30, "status": ENABLED}, True), "half")
        self.assertIsNone(self.event({"hp": 16, "max": 30}, {"hp": 14, "max": 30, "status": ENABLED}, False))

    def test_works_again_after_a_knock_out(self):
        self.assertEqual(self.event({"hp": 0, "max": 30, "out": True}, {"hp": 9, "max": 30, "status": ENABLED}, False), "back")

    # GPT review, 2026-11-27: a system that repairs to 4 while still
    # enabling and is hit back to 0 was said "disabled" twice without ever
    # working again.
    def test_not_disabled_twice_in_one_outage(self):
        self.assertIsNone(self.event({"hp": 4, "max": 30, "out": True}, {"hp": 0, "max": 30, "status": 1}, False))

    # Negative twins: small hits, a repair still under way, a first look.
    def test_quiet_otherwise(self):
        self.assertIsNone(self.event({"hp": 30, "max": 30}, {"hp": 25, "max": 30, "status": ENABLED}, True))
        self.assertIsNone(self.event({"hp": 0, "max": 30, "out": True}, {"hp": 4, "max": 30, "status": 2}, False))
        self.assertIsNone(self.event(None, {"hp": 0, "max": 30, "status": 1}, True))
        self.assertIsNone(self.event({"hp": 14, "max": 30}, {"hp": 10, "max": 30, "status": ENABLED}, True))


if __name__ == "__main__":
    unittest.main()
