"""latency_report pairs each key with the first line spoken after it."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
try:
    import latency_report  # noqa: E402
except ImportError:   # the public copy leaves the development tools out
    latency_report = None

LOG = """IO - inputCore.InputManager.executeGesture (17:02:56.198) - winInputHook (5788):
Input: kb(laptop):downArrow
IO - speech.speech.speak (17:02:56.354) - MainThread (5508):
Speaking [LangChangeCommand ('en_US'), 'Overview, 4 of 7']
IO - speech.speech.speak (17:02:56.900) - MainThread (5508):
Speaking [LangChangeCommand ('en_US'), 'not the answer']
IO - inputCore.InputManager.executeGesture (17:03:02.596) - winInputHook (5788):
Input: kb(laptop):escape
IO - inputCore.InputManager.executeGesture (17:03:05.966) - winInputHook (5788):
Input: kb(laptop):escape
IO - speech.speech.speak (17:03:06.436) - MainThread (5508):
Speaking [LangChangeCommand ('en_US'), "B'Elanna, 1 of 5"]
""".splitlines()


@unittest.skipIf(latency_report is None, "tools/latency_report.py is not in this copy")
class PairsTests(unittest.TestCase):
    def test_pairs(self):
        rows = list(latency_report.pairs(LOG))
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0][0], "kb(laptop):downArrow")
        self.assertEqual(round(rows[0][1]), 156)
        self.assertEqual(rows[0][2], "Overview, 4 of 7")
        self.assertIsNone(rows[1][1])          # the first Escape: nothing said before the next key
        self.assertEqual(round(rows[2][1]), 470)
        self.assertEqual(rows[2][2], "B'Elanna, 1 of 5")


if __name__ == "__main__":
    unittest.main()
