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

    def test_goal_back_long_after_but_right_after_a_room_change_is_on_hold(self):
        # Dark Frontier, VM, 2026-10-22: the Holodeck switched off minutes
        # after the training began; "Done: Wait until..." was said.
        on = self.mk("Dark Frontier", A)
        training = self.mk("Dark Frontier, 20 cycles left", B)
        self.q.changes(on, training)
        self.lua.execute('''
local c = os.clock; os.clock = function() return c() + 300 end
package.loaded["ship"] = { state_lost_at = os.clock() - 1 }
''')
        said = self.q.changes(training, on)
        self.assertNotIn("Done:", said)
        self.assertIn("On hold: Wait until the crew completes", said)

    def test_after_a_reload_a_room_loss_still_holds(self):
        # The requirement was never seen done in this run (a save loaded with
        # the Holodeck on), then deck 6's Life Support went off.
        on = self.mk("Dark Frontier", A)
        training = self.mk("Dark Frontier, 20 cycles left", B)
        self.lua.execute('package.loaded["ship"] = { state_lost_at = os.clock() + 0.5 }')
        said = self.q.changes(training, on)
        self.assertIn("On hold: Wait until the crew completes", said)

    def test_goal_finishing_as_a_room_goes_off_is_still_done(self):
        # A research that completes in the same moment some room is switched
        # off, with nothing new in its mission, is done (Fable review).
        before = self.lua.eval('''function() return {
            { name = "Endgame", goals = { "Research Admiral Janeway's medical data.", "Collect 50 Dilithium." } } } end''')()
        after = self.mk("Endgame", "Collect 50 Dilithium.")
        self.lua.execute('package.loaded["ship"] = { state_lost_at = os.clock() }')
        said = self.q.changes(before, after)
        self.assertIn("Done: Research Admiral Janeway", said)
        self.assertNotIn("On hold", said)

    def test_room_back_on_finishes_the_requirement(self):
        # Then Life Support on: the requirement goes, the training returns.
        on = self.mk("Dark Frontier", A)
        training = self.mk("Dark Frontier, 20 cycles left", B)
        self.lua.execute('package.loaded["ship"] = { state_lost_at = os.clock() - 30 }')
        said = self.q.changes(on, training)
        self.assertIn("Done: You need an active HOLO DECK", said)
        self.assertNotIn("On hold", said)

    def test_room_change_long_ago_does_not_hold(self):
        # The negative twin: the same return with the last room change far
        # back is still "Done".
        on = self.mk("Dark Frontier", A)
        training = self.mk("Dark Frontier, 20 cycles left", B)
        self.q.changes(on, training)
        self.lua.execute('''
local c = os.clock; os.clock = function() return c() + 300 end
package.loaded["ship"] = { state_lost_at = os.clock() - 200 }
''')
        said = self.q.changes(training, on)
        self.assertIn("Done: Wait until the crew completes", said)


if __name__ == "__main__":
    unittest.main()
