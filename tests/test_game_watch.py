"""game_watch: each new announcement, DLC and installed build is reported
once, the first run reports nothing, and a check that failed keeps the old
state instead of reporting everything as new later (2026-10-26)."""
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent / "tools"
sys.path.insert(0, str(TOOLS))
try:
    import game_watch  # noqa: E402
except ImportError:   # the public copy may leave the tool out
    game_watch = None

NEWS = {"appnews": {"newsitems": [
    {"gid": "2", "date": 1792600000, "title": "Delta Chronicles 2", "url": "u2"},
    {"gid": "1", "date": 1791000000, "title": "Patch 2.1", "url": "u1"}]}}
STORE = {"2643390": {"success": True, "data": {"dlc": [11, 12]}}}


@unittest.skipIf(game_watch is None, "tools/game_watch.py is not in this copy")
class CompareTests(unittest.TestCase):
    def test_parsing(self):
        self.assertEqual([n[0] for n in game_watch.news_items(NEWS)], ["2", "1"])
        self.assertEqual(game_watch.dlc_ids(STORE), ["11", "12"])
        self.assertIsNone(game_watch.dlc_ids({"2643390": {"success": False}}))

    def test_first_run_is_silent(self):
        lines, state = game_watch.compare({}, game_watch.news_items(NEWS), ["11", "12"], "100")
        self.assertEqual(lines, [])
        self.assertEqual(state["news"], ["1", "2"])
        self.assertEqual(state["build"], "100")

    def test_nothing_changed_is_silent(self):
        _, state = game_watch.compare({}, game_watch.news_items(NEWS), ["11", "12"], "100")
        lines, _ = game_watch.compare(state, game_watch.news_items(NEWS), ["11", "12"], "100")
        self.assertEqual(lines, [])

    def test_each_change_reported_once(self):
        _, state = game_watch.compare({}, game_watch.news_items(NEWS)[1:], ["11"], "100")
        lines, state = game_watch.compare(state, game_watch.news_items(NEWS), ["11", "12"], "101",
                                          dlc_name=lambda i: "Equinox" if i == "12" else i)
        self.assertEqual(len(lines), 3)
        self.assertIn("Delta Chronicles 2", lines[0])
        self.assertIn("Equinox (app 12)", lines[1])
        self.assertIn("build 100 to 101", lines[2])
        again, _ = game_watch.compare(state, game_watch.news_items(NEWS), ["11", "12"], "101")
        self.assertEqual(again, [])

    def test_failed_check_keeps_state(self):
        _, state = game_watch.compare({}, game_watch.news_items(NEWS), ["11"], "100")
        lines, kept = game_watch.compare(state, None, None, None)
        self.assertEqual(lines, [])
        self.assertEqual(kept, state)


if __name__ == "__main__":
    unittest.main()
