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


if __name__ == "__main__":
    unittest.main()
