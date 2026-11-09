"""A room in the build ring says its effect and costs before its description.

Casey, 2026-11-08, his own play: after "Observation Lounge. Missing
technology. 3 spaces wide, fits here. 6 of 6." came the description before
"Raises MORALE by +6 per CYCLE" and the costs. He chose: effect, then
construction, then operation, the description last. Runs the real
construction.lua under lupa (the split of the game's description text).
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
for _, m in ipairs({ "speech", "screen", "ship", "text", "tr" }) do package.preload[m] = function() return nop end end
function FindAllOf() return {} end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class RingEffectsTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('construction'))")

    def split(self, desc):
        prose, effects = self.M.split_desc(desc)
        return prose, effects

    def test_effects_are_the_sentences_with_numbers(self):
        prose, effects = self.split(
            "A social hub for the crew, the Observation Lounge features a full bar. "
            "Raises MORALE by +6 per CYCLE. Reduces maximum HULL by -30.")
        self.assertEqual(effects, "Raises MORALE by +6 per CYCLE. Reduces maximum HULL by -30.")
        self.assertEqual(prose, "A social hub for the crew, the Observation Lounge features a full bar.")

    # Negative twin: a description with no figures stays whole, no effects.
    def test_no_numbers_no_effects(self):
        prose, effects = self.split("The ship's primary medical facility. Heals crew over time.")
        self.assertEqual(effects, "")
        self.assertEqual(prose, "The ship's primary medical facility. Heals crew over time.")


if __name__ == "__main__":
    unittest.main()
