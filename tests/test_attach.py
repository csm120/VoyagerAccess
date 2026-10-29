"""The helper's side of being started by the mod (Casey, 2026-10-29).

The helper writes the time to helper-alive.txt while it serves, so the mod
can tell no helper is running; --attach joins a game that is already
running instead of starting it.
"""
import queue
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager import app, helper  # noqa: E402


class AliveFileTests(unittest.TestCase):
    def test_the_loop_writes_the_time(self):
        with tempfile.TemporaryDirectory() as d:
            alive = Path(d) / "helper-alive.txt"
            checks = []

            def keep_going():
                checks.append(1)
                return len(checks) < 2

            class Tailer:
                def read_lines(self):
                    return []

            with mock.patch.object(helper, "HELPER_ALIVE", alive), \
                    mock.patch.object(helper.time, "time", return_value=1234.5):
                helper._serve_loop(None, Tailer(), keep_going, None, lambda t: None,
                                   lambda w, fn, *a: fn(*a), queue.Queue())
            self.assertEqual(alive.read_text(encoding="utf-8"), "1234")


class AttachTests(unittest.TestCase):
    def test_attach_is_an_option(self):
        with mock.patch.object(app, "attach_game", return_value=0) as a, \
                mock.patch.object(app, "setup_logging"):
            self.assertEqual(app.main(["--attach"]), 0)
        a.assert_called_once()

    def test_a_second_helper_leaves_at_once(self):
        with mock.patch.object(app, "single_instance", return_value=False), \
                mock.patch.object(app, "play_session") as play:
            self.assertEqual(app.attach_game(), 0)
        play.assert_not_called()

    def test_no_game_running_means_nothing_to_join(self):
        with mock.patch.object(app, "single_instance", return_value=True), \
                mock.patch.object(app.modfiles, "game_is_running", return_value=False), \
                mock.patch.object(app, "play_session") as play:
            self.assertEqual(app.attach_game(), 0)
        play.assert_not_called()

    def test_a_running_game_is_joined_and_said(self):
        with mock.patch.object(app, "single_instance", return_value=True), \
                mock.patch.object(app.modfiles, "game_is_running", return_value=True), \
                mock.patch.object(app, "play_session", return_value=0) as play:
            self.assertEqual(app.attach_game(), 0)
        play.assert_called_once()
        self.assertIn("Voyager Access speech started", play.call_args.kwargs.get("greeting", ""))


if __name__ == "__main__":
    unittest.main()
