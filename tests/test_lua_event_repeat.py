"""An event's next step does not read its story again.

Casey, 2026-11-08 (Initiations): CONTINUE after "... claim his warrior name.
Outcome: good." closed the event window and opened a new one for the next
step with the same story, and the whole story was read again before the
options. Runs the real popups.lua under lupa (the rule only).
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
function FindAllOf() return {} end
function StaticFindObject() return nil end
function RegisterHook() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay(_, fn) fn() end
function LoopAsync() end
"""

STORY = ("Initiations. The Kazon ship responds to the hail. He states that he must \"deal\" "
         "with the captured crew to claim his warrior name.")


@unittest.skipIf(lupa is None, "lupa not installed")
class EventRepeatTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('popups'))")

    def test_same_story_after_the_result_is_a_repeat(self):
        self.assertTrue(self.M.event_repeat(STORY + " Outcome: good.", STORY))

    def test_story_heard_from_the_scan_panel_is_a_repeat(self):
        # Falling Station (Casey, 2026-11-08): the scan's panel said the story,
        # and the event window on arrival 14 s later said it again.
        panel = "Class D Planet, in system 5 oh 8 8 point 2. Cold-Zone. " + STORY
        self.assertTrue(self.M.event_repeat(panel, STORY))

    def test_away_mission_drops_the_story_the_view_said(self):
        # A risky plan (Casey, 2026-11-08): the System map line said the
        # mission's text, and the away mission said it again 16 s later.
        story = ("Following Commander Chakotay's plan, we modified a coil scanner and are ready now "
                 "to send a small away team to Culluh's raider.")
        view = "System map. Kazon Raider, main mission, Online, Maneuvers, " + story
        self.assertEqual(self.M.drop_heard("Away mission: A risky plan. " + story + " Choose 3 heroes.", view),
                         "Away mission: A risky plan. Choose 3 heroes.")

    def test_drop_heard_keeps_short_and_unheard_sentences(self):
        self.assertEqual(self.M.drop_heard("Choose 3 heroes. A new long sentence that nobody has heard yet today.",
                                           "Choose 3 heroes."),
                         "Choose 3 heroes. A new long sentence that nobody has heard yet today.")

    def test_a_last_sentence_without_a_stop_is_kept(self):
        story = "Following Commander Chakotay's plan, we modified a coil scanner and are ready now."
        self.assertEqual(self.M.drop_heard(story + " Recommended skills: Engineering", story),
                         "Recommended skills: Engineering")
        self.assertFalse(self.M.event_repeat(STORY, STORY + " Online"))

    def test_away_place_line_dropped_after_arrival(self):
        # Drayan II (Casey, 2026-11-08): "Arrived at Drayan II", then the away
        # mission opened with "Drayan II, system 3 7 7 6 point 1."
        self.assertTrue(self.M.place_heard("Drayan II, system 3 7 7 6 point 1.",
                                           self.lua.table_from(["Under way to Drayan II", "Arrived at Drayan II"])))

    def test_away_place_line_kept_for_a_new_place(self):
        self.assertFalse(self.M.place_heard("Drayan II, system 3 7 7 6 point 1.",
                                            self.lua.table_from(["Arrived at Kazon Raider"])))
        self.assertFalse(self.M.place_heard("Drayan II, system 3 7 7 6 point 1.", self.lua.table_from([])))
        # "Drayan I" is not heard in "Drayan II" (review, 2026-11-08).
        self.assertFalse(self.M.place_heard("Drayan I, system 3 7 7 6 point 1.",
                                            self.lua.table_from(["Arrived at Drayan II"])))
        self.assertTrue(self.M.place_heard("Drayan I, system 3 7 7 6 point 1.",
                                           self.lua.table_from(["Arrived at Drayan I"])))

    # Negative twins: a new sentence, or nothing heard before.
    def test_new_sentence_is_not_a_repeat(self):
        self.assertFalse(self.M.event_repeat(STORY, STORY + " The boy lowers his weapon."))

    def test_nothing_before_is_not_a_repeat(self):
        self.assertFalse(self.M.event_repeat(None, STORY))


if __name__ == "__main__":
    unittest.main()
