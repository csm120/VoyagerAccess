import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager.helper import (  # noqa: E402
    VK, VK_CAPITAL, VK_CONTROL, VK_INSERT, VK_MENU, VK_SHIFT, KeyWatcher, Tailer, is_center_mouse, is_game_exe, parse_click, parse_line, parse_ring)


class ParseLineTests(unittest.TestCase):
    def test_interrupt_and_queue(self):
        self.assertEqual(parse_line("I|Settings\n"), (True, "Settings"))
        self.assertEqual(parse_line("Q|Load Game\r\n"), (False, "Load Game"))

    def test_rejects_bad_lines(self):
        for bad in ["", "I|", "I|   ", "X|text", "Itext", "settings"]:
            self.assertIsNone(parse_line(bad), bad)


class ParseClickTests(unittest.TestCase):
    def test_click(self):
        self.assertEqual(parse_click("C|640,360\n"), (640, 360))
        self.assertEqual(parse_click("C|640.6,359.4"), (641, 359))

    def test_not_a_click(self):
        for bad in ["I|640,360", "C|", "C|640", "C|a,b", "C|1,2,3"]:
            self.assertIsNone(parse_click(bad), bad)

    def test_click_is_not_speech(self):
        self.assertIsNone(parse_line("C|640,360"))


class ParseCenterTests(unittest.TestCase):
    # Set course takes its target from under the mouse cursor (2026-10-14).
    def test_center(self):
        self.assertTrue(is_center_mouse("M|center\n"))

    def test_not_center(self):
        for bad in ["M|", "M|left", "C|640,360", "I|center", "center"]:
            self.assertFalse(is_center_mouse(bad), bad)

    def test_ring(self):
        # A radial menu segment, as an offset from the ring's centre in ring
        # radii (2026-10-14: its details only show on mouse hover).
        self.assertEqual(parse_ring("M|ring,0,-1\n"), (0.0, -1.0))
        self.assertEqual(parse_ring("M|ring,0.866,0.5"), (0.866, 0.5))

    def test_ring_click(self):
        # The same offset, then a real left click: Set course takes a point
        # next to Voyager only once a click has selected it (demo, VM,
        # 2026-10-15).
        from voyager.helper import parse_ring_click
        self.assertEqual(parse_ring_click("M|ringclick,0.1,-0.2\n"), (0.1, -0.2))
        for bad in ["M|ringclick", "M|ringclick,1", "M|ringclick,a,b", "M|ring,0,1", "C|1,2"]:
            self.assertIsNone(parse_ring_click(bad), bad)
        self.assertIsNone(parse_ring("M|ringclick,0,1"))
        self.assertIsNone(parse_line("M|ringclick,0,1"))
        self.assertIsNone(parse_click("M|ringclick,0,1"))

    def test_not_ring(self):
        for bad in ["M|ring", "M|ring,1", "M|ring,a,b", "M|center", "C|1,2", "M|ring,1,2,3"]:
            self.assertIsNone(parse_ring(bad), bad)

    def test_center_is_not_speech_or_click(self):
        self.assertIsNone(parse_line("M|center"))
        self.assertIsNone(parse_click("M|center"))


class TailerTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / "speech.txt"

    def tearDown(self):
        self.dir.cleanup()

    def append(self, data):
        with open(self.path, "ab") as f:
            f.write(data)

    def test_skips_lines_written_before_start(self):
        self.append(b"I|old\n")
        t = Tailer(self.path)
        self.assertEqual(t.read_lines(), [])
        self.append(b"I|new\n")
        self.assertEqual(t.read_lines(), ["I|new"])

    def test_missing_file_then_created(self):
        t = Tailer(self.path)
        self.assertEqual(t.read_lines(), [])
        self.append(b"Q|one\nQ|two\n")
        self.assertEqual(t.read_lines(), ["Q|one", "Q|two"])

    def test_holds_back_partial_line(self):
        t = Tailer(self.path)
        self.append(b"I|Hal")
        self.assertEqual(t.read_lines(), [])
        self.append(b"f\n")
        self.assertEqual(t.read_lines(), ["I|Half"])

    def test_restarts_after_truncation(self):
        self.append(b"I|aaaaaaaaaaaaaaaa\n")
        t = Tailer(self.path)
        self.path.write_bytes(b"I|after reset\n")
        self.assertEqual(t.read_lines(), ["I|after reset"])

    def test_utf8(self):
        t = Tailer(self.path)
        self.append("Q|Café\n".encode("utf-8"))
        self.assertEqual(t.read_lines(), ["Q|Café"])


DOWN, TAPPED = 0x8000, 0x0001


class FakeKeyboard:
    """Key states by virtual-key code, read the way GetAsyncKeyState is."""

    def __init__(self):
        self.state = {}

    def __call__(self, vk):
        s = self.state.get(vk, 0)
        self.state[vk] = s & DOWN   # the "tapped" bit clears once read
        return s


class KeyWatcherTests(unittest.TestCase):
    def setUp(self):
        self.kb = FakeKeyboard()
        self.front = True
        self.w = KeyWatcher(self.kb, lambda: self.front)

    def test_press_reports_once_while_held(self):
        self.kb.state[VK["enter"]] = DOWN
        self.assertEqual(self.w.poll(), ["enter"])
        self.assertEqual(self.w.poll(), [])
        self.kb.state[VK["enter"]] = 0
        self.assertEqual(self.w.poll(), [])
        self.kb.state[VK["enter"]] = DOWN
        self.assertEqual(self.w.poll(), ["enter"])

    def test_tap_between_polls_still_counts(self):
        self.kb.state[VK["r"]] = TAPPED
        self.assertEqual(self.w.poll(), ["r"])

    def test_shift_enter_is_its_own_key(self):
        self.kb.state[VK["enter"]] = DOWN
        self.kb.state[VK_SHIFT] = DOWN
        self.assertEqual(self.w.poll(), ["shift+enter"])

    def test_screen_reader_and_ctrl_alt_chords_ignored(self):
        for mod in (VK_INSERT, VK_CAPITAL, VK_CONTROL, VK_MENU):
            self.kb.state = {VK["r"]: DOWN, mod: DOWN}
            self.assertEqual(self.w.poll(), [], hex(mod))
            self.kb.state = {}
            self.w.poll()

    def test_ctrl_f12_is_the_one_ctrl_chord(self):
        # Casey, 2026-10-11: Ctrl+F12 opens What's new in the game.
        self.kb.state = {VK["f12"]: DOWN, VK_CONTROL: DOWN}
        self.assertEqual(self.w.poll(), ["ctrl+f12"])
        self.kb.state = {}
        self.w.poll()
        # Other Ctrl chords, and F12 with a screen reader key, stay ignored.
        self.kb.state = {VK["c"]: DOWN, VK_CONTROL: DOWN}
        self.assertEqual(self.w.poll(), [])
        self.kb.state = {}
        self.w.poll()
        self.kb.state = {VK["f12"]: DOWN, VK_CONTROL: DOWN, VK_INSERT: DOWN}
        self.assertEqual(self.w.poll(), [])

    def test_ctrl_f1_opens_the_key_list(self):
        # Casey, 2026-10-14: a list of every key, browsable in the game.
        self.kb.state = {VK["f1"]: DOWN, VK_CONTROL: DOWN}
        self.assertEqual(self.w.poll(), ["ctrl+f1"])
        self.kb.state = {}
        self.w.poll()
        # With a screen reader key also down it stays the screen reader's.
        self.kb.state = {VK["f1"]: DOWN, VK_CONTROL: DOWN, VK_INSERT: DOWN}
        self.assertEqual(self.w.poll(), [])

    def test_nothing_when_game_not_in_front(self):
        self.front = False
        self.kb.state[VK["up"]] = DOWN
        self.assertEqual(self.w.poll(), [])
        # Still held when the game comes back: not a new press.
        self.front = True
        self.assertEqual(self.w.poll(), [])

    def test_all_keys_named(self):
        self.assertEqual(sorted(VK), sorted(
            ["enter", "backspace", "escape", "up", "down", "left", "right", "r", "o", "i", "n", "grave", "f1", "pageup", "pagedown", "home", "end", "c", "v", "j", "f12"]))

    def test_escape_reaches_the_mod(self):
        # Escape opened the game's pause menu while the mod's C list kept
        # the arrow keys (2026-10-14): the mod has to hear it to close lists.
        self.kb.state[VK["escape"]] = DOWN
        self.assertEqual(self.w.poll(), ["escape"])


class GameExeTests(unittest.TestCase):
    def test_demo_and_full_game_exes(self):
        # The full game's exe has "Steam" in its name (2026-10-14).
        self.assertTrue(is_game_exe("C:/Steam/Demo/STVoyager-Win64-Shipping.exe"))
        self.assertTrue(is_game_exe("C:/Steam/Full/STVoyagerSteam-Win64-Shipping.exe"))
        self.assertFalse(is_game_exe("C:/Windows/notepad.exe"))


if __name__ == "__main__":
    unittest.main()
