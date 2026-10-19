"""quest.lua's M.changes decides what an objective update says. A goal that
went away was always called "Done": switching the Holodeck off brought back
"You need an active HOLO DECK" and dropped the training goal, which was said
as "Done: Wait until the crew completes..." (Dark Frontier, VM, 2026-10-18).

Runs the real Lua through lupa (py -3.11 -m pip install --user lupa); skipped
when lupa is not installed."""
import unittest
from pathlib import Path

try:
    import lupa
except ImportError:
    lupa = None

QUEST = Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts" / "quest.lua"

A = "You need an active HOLO DECK to proceed."
B = "Wait until the crew completes their simulation training."


@unittest.skipIf(lupa is None, "lupa not installed")
class ChangesTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime()
        self.lua.execute('''
package.preload["speech"] = function() return { say = function() end } end
package.preload["screen"] = function() return {} end
package.preload["popups"] = function() return {} end
package.preload["crumb"] = function() return { at = function() end } end
''')
        self.q = self.lua.execute(QUEST.read_text(encoding="utf-8"))
        self.mk = self.lua.eval("function(name, g) return { { name = name, goals = { g } } } end")

    def test_finished_goal_is_done(self):
        said = self.q.changes(self.mk("Dark Frontier", A), self.mk("Dark Frontier, 20 cycles left", B))
        self.assertTrue(said.startswith("Done: You need an active HOLO DECK"), said)

    def test_goal_that_comes_back_puts_the_other_on_hold(self):
        on = self.mk("Dark Frontier", A)
        training = self.mk("Dark Frontier, 20 cycles left", B)
        self.q.changes(on, training)
        said = self.q.changes(training, on)
        self.assertNotIn("Done:", said)
        self.assertIn("On hold: Wait until the crew completes", said)


    def test_goal_back_after_real_progress_is_still_done(self):
        # "Accept COMMS request" done, research added; minutes later the
        # research is finished and COMMS comes back as the next step.
        comms = self.mk("Endgame", "Accept COMMS request.")
        research = self.mk("Endgame", "Research Admiral Janeway's medical data in the SCIENCE LABORATORY.")
        self.q.changes(comms, research)
        self.lua.execute("local c = os.clock; local base = c(); os.clock = function() return c() + 60 end")
        said = self.q.changes(research, comms)
        self.assertIn("Done: Research Admiral Janeway", said)
        self.assertNotIn("On hold", said)


if __name__ == "__main__":
    unittest.main()
