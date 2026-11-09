"""A room in the build ring says where it fits and its place in the list early.

Casey, 2026-11-08, his own play: "Large Cargo Bay. Missing technology." was
followed by the description, storage, costs and size before "3 of 5"; he had
to listen through all of it. He chose: name, reason, fit and place first, the
details after. Runs the real focus.lua under lupa (ring_order only; that
radial_focus calls it is checked by hearing it).
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
for _, m in ipairs({ "speech", "screen", "crumb", "keys", "popups", "ship", "construction", "text", "hints", "tr" }) do
    package.preload[m] = function() return nop end
end
package.preload["popups"] = function()
    return setmetatable({ SAVE_WARNINGS = {}, ROOM_WARNINGS = {} }, { __index = function() return function() end end })
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

TEXT = ("Large Cargo Bay. Missing technology. Advanced storage facility that massively increases "
        "storage. Operation: energy 8, crew 5. Construction: 120 Duranium, 1 work team, 20 cycles")
CHECK = "Advanced storage facility that"
FIT = "6 spaces wide and 2 decks tall, does not fit: this empty space is 1 wide"


@unittest.skipIf(lupa is None, "lupa not installed")
class RingOrderTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('focus'))")

    def test_fit_and_place_before_the_description(self):
        self.assertEqual(
            self.M.ring_order(TEXT, CHECK, FIT, "3 of 5"),
            "Large Cargo Bay. Missing technology. " + FIT + ". 3 of 5. Advanced storage facility that "
            "massively increases storage. Operation: energy 8, crew 5. Construction: 120 Duranium, "
            "1 work team, 20 cycles")

    # Negative twin: with no description to find, both go at the end as before.
    def test_no_description_keeps_the_end(self):
        self.assertEqual(self.M.ring_order("Shuttle Bay. Operation: energy 2", None, FIT, "1 of 5"),
                         "Shuttle Bay. Operation: energy 2. " + FIT + ". 1 of 5")

    def test_no_fit_no_place(self):
        self.assertEqual(self.M.ring_order(TEXT, CHECK, None, ""), TEXT)


if __name__ == "__main__":
    unittest.main()
