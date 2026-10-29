"""Opening speech: a Tolk that will not load falls back to Windows speech,
and the screen reader in use is logged at every launch.

Before 2026-10-29 Tolk() sat outside any try in launch_game, so a missing
or blocked Tolk.dll ended the helper with no speech and no log line, and
the screen reader's name was never logged (the WFH session's reliability
review).
"""
import logging
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager import helper  # noqa: E402


class FakeTolk:
    def __init__(self, folder):
        self.folder = folder

    def name(self):
        return "NVDA"


class BrokenTolk:
    def __init__(self, folder):
        raise OSError("Tolk.dll could not be loaded")


class FakeFallback:
    def __init__(self):
        self.said = []

    def name(self):
        return "Windows speech"

    def say(self, text, interrupt):
        self.said.append(text)


class OpenSpeechTests(unittest.TestCase):
    def test_tolk_loads_and_the_screen_reader_is_logged(self):
        with self.assertLogs("voyager.helper", level="INFO") as cm:
            s = helper.open_speech("x", tolk_cls=FakeTolk, fallback_cls=FakeFallback)
        self.assertIsInstance(s, FakeTolk)
        self.assertTrue(any("NVDA" in m for m in cm.output))

    def test_a_tolk_that_will_not_load_falls_back_and_says_so(self):
        with self.assertLogs("voyager.helper", level="INFO") as cm:
            s = helper.open_speech("x", tolk_cls=BrokenTolk, fallback_cls=FakeFallback)
        self.assertIsInstance(s, FakeFallback)
        self.assertTrue(any("could not be loaded" in m for m in cm.output))
        self.assertEqual(len(s.said), 1)


class TolkOutputTests(unittest.TestCase):
    def test_a_refused_line_is_logged_once(self):
        class Dll:
            def Tolk_Output(self, text, interrupt):
                return False

        t = helper.Tolk.__new__(helper.Tolk)
        t.dll = Dll()
        with self.assertLogs("voyager.helper", level="INFO") as cm:
            t.say("one", True)
            t.say("two", True)
        self.assertEqual(len([m for m in cm.output if "refused" in m]), 1)


if __name__ == "__main__":
    unittest.main()
