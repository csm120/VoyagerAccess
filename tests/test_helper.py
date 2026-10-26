import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager.helper import (  # noqa: E402
    VK, VK_CAPITAL, VK_CONTROL, VK_F11, VK_INSERT, VK_MENU, VK_SHIFT, KeyWatcher, Tailer, enable_dpi_awareness, is_center_mouse, is_game_exe,
    parse_click, parse_line, parse_ring)


class FakeUser32:
    def __init__(self, result):
        self.result, self.calls = result, []

    def SetProcessDpiAwarenessContext(self, ctx):
        self.calls.append(ctx.value)
        return self.result


class DpiAwarenessTests(unittest.TestCase):
    def test_asks_for_per_monitor_v2(self):
        user32 = FakeUser32(1)
        self.assertEqual(enable_dpi_awareness(user32), "per-monitor v2")
        import ctypes
        self.assertEqual(user32.calls, [ctypes.c_void_p(-4).value])  # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2

    def test_falls_back_when_refused(self):
        # Refused (already set, or an old Windows): the shcore fallback runs
        # or nothing is set; the helper never stops over it.
        self.assertIn(enable_dpi_awareness(FakeUser32(0)), ("per-monitor", None))


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

    def test_ctrl_f11_switches_the_input_log_and_f11_alone_does_nothing(self):
        # The mod's keys always come from the watcher, so it must see F11.
        self.kb.state[VK_F11] = DOWN
        self.assertEqual(self.w.poll(), [])
        self.kb.state[VK_F11] = 0
        self.w.poll()
        self.kb.state[VK_CONTROL] = DOWN
        self.kb.state[VK_F11] = DOWN
        self.assertEqual(self.w.poll(), ["ctrl+f11"])

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
            ["enter", "backspace", "escape", "up", "down", "left", "right", "r", "o", "i", "n", "grave", "f1", "pageup", "pagedown", "home", "end", "c", "v", "j", "h", "f12"]))

    def test_escape_reaches_the_mod(self):
        # Escape opened the game's pause menu while the mod's C list kept
        # the arrow keys (2026-10-14): the mod has to hear it to close lists.
        self.kb.state[VK["escape"]] = DOWN
        self.assertEqual(self.w.poll(), ["escape"])


class KeyEventsTests(unittest.TestCase):
    """The input log and the mod's keys from Windows' own key events
    (firefly82, 2026-10-21: an E that did nothing could not be told from
    one never pressed)."""

    def setUp(self):
        from voyager.helper import KeyEvents
        self.front = True
        self.ev = KeyEvents(lambda: self.front, now=lambda: "T")

    def test_game_key_is_logged_with_hold_but_is_no_mod_key(self):
        self.assertEqual(self.ev.key(0x45, True, 1000, False), ([], "T E down"))
        self.assertEqual(self.ev.key(0x45, False, 1080, False), ([], "T E up after 80 ms"))

    def test_typed_letters_are_not_written_to_the_log(self):
        # Profile and save names, or the Steam overlay over the game, would
        # otherwise go letter by letter into UE4SS.log, which players paste
        # into public bug reports. E, F and T (the game's quick actions) and
        # the mod's own keys are still named.
        self.assertEqual(self.ev.key(0x4B, True, 0, False), ([], "T a character key down"))       # K
        self.assertEqual(self.ev.key(0x4B, False, 50, False), ([], "T a character key up after 50 ms"))
        self.assertEqual(self.ev.key(0x37, True, 60, False)[1], "T a character key down")        # 7
        self.assertEqual(self.ev.key(0xBE, True, 70, False)[1], "T a character key down")        # period
        self.assertEqual(self.ev.key(0x46, True, 80, False)[1], "T F down")
        self.assertEqual(self.ev.key(VK["j"], True, 90, False)[1], "T J down (mod key: j)")

    def test_release_after_leaving_the_game_is_not_logged(self):
        # Held while switching to another window: the release happened
        # outside the game, so it is not written (GPT review, 2026-10-21).
        self.ev.key(0x45, True, 0, False)
        self.front = False
        self.assertEqual(self.ev.key(0x45, False, 300, False), ([], None))
        self.front = True
        self.assertEqual(self.ev.mouse(0x201, 5, 5, 0, False), "T mouse left down at 5,5, by the player")
        self.front = False
        self.assertIsNone(self.ev.mouse(0x202, 900, 10, 40, False))

    def test_only_a_players_press_of_a_game_key_counts_as_seen(self):
        # "seen" ends the mod's speech hold. Enter's release 0.1 s after it
        # opened a room window ended it, and the focused button cut the
        # window off (Casey, 2026-10-26); the mod's own clicks must not
        # either. A game key pressed soon after a mod key still counts.
        from voyager.helper import player_press
        e_down = self.ev.key(0x45, True, 0, False)
        e_up = self.ev.key(0x45, False, 80, False)
        enter_down = self.ev.key(VK["enter"], True, 100, False)
        enter_up = self.ev.key(VK["enter"], False, 900, False)
        self.assertTrue(player_press(*e_down))
        self.assertFalse(player_press(*e_up))
        self.assertFalse(player_press(*enter_down))
        self.assertFalse(player_press(*enter_up))
        self.assertTrue(player_press([], self.ev.mouse(0x201, 5, 5, 0, False)))
        self.assertFalse(player_press([], self.ev.mouse(0x202, 5, 5, 40, False)))
        self.assertFalse(player_press([], self.ev.mouse(0x201, 5, 5, 50, True)))
        self.assertFalse(player_press([], None))

    def test_screen_reader_commands_are_no_press(self):
        # NVDA+Up to hear a line again must not end the hold on what the
        # mod is reading (Fable review, 2026-10-26). Ctrl alone still does.
        from voyager.helper import player_press
        self.assertFalse(player_press(*self.ev.key(VK_INSERT, True, 0, False)))
        self.assertFalse(player_press(*self.ev.key(VK["r"], True, 10, False)))   # R with Insert
        self.ev.key(VK["r"], False, 50, False)
        self.ev.key(VK_INSERT, False, 60, False)
        self.assertFalse(player_press(*self.ev.key(VK_CAPITAL, True, 100, False)))
        self.assertFalse(player_press(*self.ev.key(0x54, True, 110, False)))       # T with Caps Lock
        self.ev.key(VK_CAPITAL, False, 150, False)
        self.assertTrue(player_press(*self.ev.key(0xA2, True, 200, False)))         # Ctrl alone

    def test_mod_key_is_named_and_logged(self):
        names, line = self.ev.key(VK["enter"], True, 0, False)
        self.assertEqual(names, ["enter"])
        self.assertEqual(line, "T Enter down (mod key: enter)")

    def test_auto_repeat_is_counted_not_repeated(self):
        self.ev.key(VK["up"], True, 0, False)
        for t in (500, 533, 566):
            self.assertEqual(self.ev.key(VK["up"], True, t, False), ([], None))
        self.assertEqual(self.ev.key(VK["up"], False, 600, False)[1], "T Up up after 600 ms, 3 repeats")

    def test_shift_enter_and_sided_modifiers(self):
        self.ev.key(0xA0, True, 0, False)        # Left Shift
        names, line = self.ev.key(VK["enter"], True, 10, False)
        self.assertEqual(names, ["shift+enter"])
        self.assertEqual(line, "T Enter down with Shift (mod key: shift+enter)")

    def test_screen_reader_chord_is_logged_but_not_a_mod_key(self):
        self.ev.key(VK_INSERT, True, 0, False)
        names, line = self.ev.key(VK["r"], True, 10, False)
        self.assertEqual(names, [])
        self.assertEqual(line, "T R down with Insert")

    def test_ctrl_f12_still_reaches_the_mod(self):
        self.ev.key(0xA2, True, 0, False)        # Left Ctrl
        self.assertEqual(self.ev.key(VK["f12"], True, 5, False)[0], ["ctrl+f12"])

    def test_nothing_logged_while_game_not_in_front(self):
        self.front = False
        self.assertEqual(self.ev.key(0x45, True, 0, False), ([], None))
        # Released after the game came back: no line, it was never logged.
        self.front = True
        self.assertEqual(self.ev.key(0x45, False, 50, False), ([], None))
        # Held down when the game comes back: not a new press.
        self.front = False
        self.ev.key(VK["up"], True, 0, False)
        self.front = True
        self.assertEqual(self.ev.key(VK["up"], True, 40, False), ([], None))

    def test_ctrl_f11_switches_the_log(self):
        # firefly82, 2026-10-21: the input log can be turned off.
        self.ev.key(0xA2, True, 0, False)        # Left Ctrl
        self.assertEqual(self.ev.key(0x7A, True, 5, False)[0], ["ctrl+f11"])
        self.ev.key(0x7A, False, 50, False)
        self.ev.key(0xA2, False, 60, False)
        # F11 alone is the game's, not the mod's.
        self.assertEqual(self.ev.key(0x7A, True, 100, False)[0], [])

    def test_injected_key_is_marked(self):
        self.assertEqual(self.ev.key(0x45, True, 0, True)[1], "T E down, injected")

    def test_mouse_buttons_and_wheel(self):
        self.assertIsNone(self.ev.mouse(0x200, 5, 5, 0, False))            # moves are not logged
        self.assertEqual(self.ev.mouse(0x201, 931, 311, 100, True), "T mouse left down at 931,311, by the mod")
        self.assertEqual(self.ev.mouse(0x202, 931, 311, 130, True),
                         "T mouse left up after 30 ms at 931,311, by the mod")
        self.assertEqual(self.ev.mouse(0x20A, 10, 20, 0, False, wheel=-120),
                         "T mouse wheel -120 at 10,20, by the player")

    def test_key_names_do_not_depend_on_the_layout(self):
        from voyager.helper import key_name
        self.assertEqual([key_name(v) for v in (0x45, 0x20, 0x70, 0x7B, 0x31, 0x61, 0xA3)],
                         ["E", "Space", "F1", "F12", "1", "Numpad 1", "Right Ctrl"])
        self.assertEqual(key_name(0xFF), "key 0xFF")


class GameExeTests(unittest.TestCase):
    def test_demo_and_full_game_exes(self):
        # The full game's exe has "Steam" in its name (2026-10-14).
        self.assertTrue(is_game_exe("C:/Steam/Demo/STVoyager-Win64-Shipping.exe"))
        self.assertTrue(is_game_exe("C:/Steam/Full/STVoyagerSteam-Win64-Shipping.exe"))
        self.assertFalse(is_game_exe("C:/Windows/notepad.exe"))


if __name__ == "__main__":
    unittest.main()
