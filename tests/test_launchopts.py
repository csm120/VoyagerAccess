import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager.launchopts import add_option, edit_file, get_option, remove_option  # noqa: E402
from voyager.steam import parse_vdf  # noqa: E402

BASE = '''"UserLocalConfigStore"
{
\t"apps"
\t{
\t\t"4054540"
\t\t{
\t\t\t"OverlayAppEnable"\t\t"0"
\t\t}
\t}
\t"Software"
\t{
\t\t"Valve"
\t\t{
\t\t\t"Steam"
\t\t\t{
\t\t\t\t"apps"
\t\t\t\t{
\t\t\t\t\t"7"
\t\t\t\t\t{
\t\t\t\t\t\t"cloud"\t\t"x"
\t\t\t\t\t}
%s\t\t\t\t}
\t\t\t}
\t\t}
\t}
}
'''

DEMO_WITH = '''\t\t\t\t\t"4054540"
\t\t\t\t\t{
\t\t\t\t\t\t"LaunchOptions"\t\t"%s"
\t\t\t\t\t\t"LastPlayed"\t\t"1"
\t\t\t\t\t}
'''

DEMO_WITHOUT = '''\t\t\t\t\t"4054540"
\t\t\t\t\t{
\t\t\t\t\t\t"LastPlayed"\t\t"1"
\t\t\t\t\t}
'''


def steam_apps(text):
    return parse_vdf(text)["userlocalconfigstore"]["software"]["valve"]["steam"]["apps"]


class LaunchOptionTests(unittest.TestCase):
    def test_adds_key_to_existing_app_block(self):
        text = BASE % DEMO_WITHOUT
        new = add_option(text, "4054540", "-dx11")
        self.assertEqual(steam_apps(new)["4054540"]["launchoptions"], "-dx11")
        self.assertEqual(steam_apps(new)["4054540"]["lastplayed"], "1")
        # The overlay block of the same id outside Software is untouched.
        self.assertEqual(parse_vdf(new)["userlocalconfigstore"]["apps"]["4054540"], {"overlayappenable": "0"})

    def test_creates_app_block_when_missing(self):
        new = add_option(BASE % "", "4054540", "-dx11")
        self.assertEqual(steam_apps(new)["4054540"], {"launchoptions": "-dx11"})
        self.assertEqual(steam_apps(new)["7"], {"cloud": "x"})

    def test_appends_to_other_options_once(self):
        text = BASE % (DEMO_WITH % "-windowed")
        new = add_option(text, "4054540", "-dx11")
        self.assertEqual(get_option(new, "4054540"), "-windowed -dx11")
        self.assertEqual(add_option(new, "4054540", "-dx11"), new)

    def test_remove_restores_previous_value(self):
        text = BASE % (DEMO_WITH % "-windowed")
        new = remove_option(add_option(text, "4054540", "-dx11"), "4054540", "-dx11")
        self.assertEqual(get_option(new, "4054540"), "-windowed")

    def test_remove_when_it_was_the_only_option(self):
        text = BASE % DEMO_WITHOUT
        new = remove_option(add_option(text, "4054540", "-dx11"), "4054540", "-dx11")
        self.assertEqual(get_option(new, "4054540"), "")

    def test_remove_drops_a_line_it_created(self):
        # The VM uninstall left '"LaunchOptions" ""' behind (2026-10-11).
        text = BASE % DEMO_WITHOUT
        added = add_option(text, "4054540", "-dx11")
        self.assertEqual(remove_option(added, "4054540", "-dx11", drop_empty=True), text)

    def test_remove_drops_a_block_it_created(self):
        text = BASE % ""
        added = add_option(text, "4054540", "-dx11")
        self.assertEqual(remove_option(added, "4054540", "-dx11", drop_empty=True), text)

    def test_remove_without_option_changes_nothing(self):
        text = BASE % DEMO_WITHOUT
        self.assertEqual(remove_option(text, "4054540", "-dx11"), text)

    def test_file_edit_keeps_line_endings(self):
        # Steam writes LF; a text-mode write on Windows turned every line into
        # CRLF (VM uninstall test, 2026-10-11).
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "localconfig.vdf"
            original = (BASE % DEMO_WITHOUT).encode("utf-8")
            p.write_bytes(original)
            edit_file(p, lambda t: add_option(t, "4054540", "-dx11"))
            self.assertNotIn(b"\r\n", p.read_bytes())
            edit_file(p, lambda t: remove_option(t, "4054540", "-dx11", drop_empty=True))
            self.assertEqual(p.read_bytes(), original)

    def test_get_option(self):
        self.assertIsNone(get_option(BASE % "", "4054540"))
        self.assertEqual(get_option(BASE % (DEMO_WITH % "-dx11"), "4054540"), "-dx11")


EXE = r"C:\Users\Player\AppData\Local\Programs\VoyagerAccess\VoyagerAccess.exe"


class WrapTests(unittest.TestCase):
    """Steam starts the helper, and the helper starts the game (Casey,
    2026-10-11: nothing of ours runs at Windows sign-in)."""

    def wrapped(self, text):
        from voyager.launchopts import unescape, wrap_launch
        new, info = wrap_launch(text, "4054540", EXE)
        return new, info, unescape(get_option(new, "4054540"))

    def test_wraps_when_there_are_no_options(self):
        _, info, value = self.wrapped(BASE % DEMO_WITHOUT)
        self.assertEqual(value, '"%s" --launch %%command%%' % EXE)
        self.assertTrue(info["created"])

    def test_keeps_plain_options_after_the_game(self):
        _, _, value = self.wrapped(BASE % (DEMO_WITH % "-dx11"))
        self.assertEqual(value, '"%s" --launch %%command%% -dx11' % EXE)

    def test_wraps_inside_an_existing_command_line(self):
        _, info, value = self.wrapped(BASE % (DEMO_WITH % "LANG=x %command% -foo"))
        self.assertEqual(value, 'LANG=x "%s" --launch %%command%% -foo' % EXE)
        self.assertTrue(info["had_command"])

    def test_wrapping_twice_changes_nothing(self):
        from voyager.launchopts import wrap_launch
        once, _ = wrap_launch(BASE % (DEMO_WITH % "-dx11"), "4054540", EXE)
        twice, info = wrap_launch(once, "4054540", EXE)
        self.assertEqual(twice, once)
        self.assertIsNone(info)

    def test_file_value_is_escaped_for_steam(self):
        new, _, _ = self.wrapped(BASE % DEMO_WITHOUT)
        self.assertIn('"\\"C:\\\\Users\\\\Player', new)

    def test_unwrap_restores_every_case_exactly(self):
        from voyager.launchopts import unwrap_launch, wrap_launch
        for original in (BASE % DEMO_WITHOUT, BASE % (DEMO_WITH % "-dx11"),
                         BASE % (DEMO_WITH % "LANG=x %command% -foo"), BASE % ""):
            new, info = wrap_launch(original, "4054540", EXE)
            self.assertEqual(unwrap_launch(new, "4054540", EXE, info), original)


if __name__ == "__main__":
    unittest.main()
