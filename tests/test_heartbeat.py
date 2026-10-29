"""The helper notices when the mod stops answering while the game runs.

The mod touches heartbeat.txt about every 2 s from its keys loop. Before
2026-10-29 nothing noticed a hung game or a dead mod: keep_going only
checked that the game's process existed (the WFH session's reliability
review).
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager.helper import HeartbeatWatch  # noqa: E402


class Clock:
    def __init__(self):
        self.now = 1000.0
        self.beat = None     # mtime of heartbeat.txt, None while missing

    def time(self):
        return self.now

    def mtime(self):
        return self.beat


def make(clock, stale=10):
    said = []
    w = HeartbeatWatch(stale=stale, now=clock.time, mtime=clock.mtime)
    return w, said


class HeartbeatTests(unittest.TestCase):
    def test_nothing_before_the_first_beat(self):
        c = Clock()
        w, said = make(c)
        for _ in range(60):
            c.now += 1
            w.check(said.append)
        self.assertEqual(said, [])

    def test_a_beat_from_before_the_session_does_not_arm_it(self):
        c = Clock()
        c.beat = 900.0
        w, said = make(c)
        for _ in range(30):
            c.now += 1
            w.check(said.append)
        self.assertEqual(said, [])

    def test_fresh_beats_say_nothing(self):
        c = Clock()
        w, said = make(c)
        for _ in range(60):
            c.now += 1
            c.beat = c.now - 1
            w.check(said.append)
        self.assertEqual(said, [])

    def test_lost_contact_is_said_once(self):
        c = Clock()
        w, said = make(c)
        c.now += 1
        c.beat = c.now
        w.check(said.append)
        for _ in range(40):
            c.now += 1
            w.check(said.append)
        self.assertEqual(said, ["Voyager Access lost contact with the game."])

    def test_contact_back_is_said_after_a_loss(self):
        c = Clock()
        w, said = make(c)
        c.now += 1
        c.beat = c.now
        w.check(said.append)
        c.now += 15
        w.check(said.append)
        c.beat = c.now
        c.now += 1
        w.check(said.append)
        self.assertEqual(said, ["Voyager Access lost contact with the game.",
                                "Voyager Access is in contact with the game again."])


if __name__ == "__main__":
    unittest.main()
