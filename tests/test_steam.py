import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager.steam import DEMO, FULL, find_games, parse_vdf  # noqa: E402

LIBRARY = r'''"libraryfolders"
{
	"0"
	{
		"path"		"%s"
		"apps"
		{
			"228980"		"128606066"
			"4054540"		"9055479762"
		}
	}
	"1"
	{
		"path"		"%s"
		"apps"
		{
			"2643390"		"1"
		}
	}
}
'''

MANIFEST = '''"AppState"
{
	"appid"		"%s"
	"name"		"Star Trek: Voyager - Across the Unknown%s"
	"installdir"		"%s"
}
'''


class ParseVdfTests(unittest.TestCase):
    def test_nested_and_escapes(self):
        data = parse_vdf('"a"\n{\n\t"path"\t\t"C:\\\\Steam"\n\t"b" { "c" "d" }\n}\n')
        self.assertEqual(data, {"a": {"path": "C:\\Steam", "b": {"c": "d"}}})

    def test_keys_are_case_insensitive(self):
        self.assertEqual(parse_vdf('"AppState" { "InstallDir" "x" }')["appstate"]["installdir"], "x")


class FindGamesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.steam = root / "Steam"
        self.lib2 = root / "D" / "SteamLibrary"
        for lib in (self.steam, self.lib2):
            (lib / "steamapps").mkdir(parents=True)
        esc = lambda p: str(p).replace("\\", "\\\\")  # noqa: E731
        (self.steam / "steamapps" / "libraryfolders.vdf").write_text(
            LIBRARY % (esc(self.steam), esc(self.lib2)))

    def tearDown(self):
        self.tmp.cleanup()

    def install(self, lib, appid, folder, suffix="", exe="STVoyager-Win64-Shipping.exe"):
        (lib / "steamapps" / f"appmanifest_{appid}.acf").write_text(MANIFEST % (appid, suffix, folder))
        win64 = lib / "steamapps" / "common" / folder / "STVoyager" / "Binaries" / "Win64"
        win64.mkdir(parents=True)
        (win64 / exe).write_bytes(b"")
        return win64

    def test_finds_the_full_game_by_its_own_exe_name(self):
        # The full game's exe is STVoyagerSteam-Win64-Shipping.exe; only the
        # demo's lacks "Steam" (2026-10-14: the full game was not found).
        full = self.install(self.steam, FULL, "Voyager", exe="STVoyagerSteam-Win64-Shipping.exe")
        self.assertEqual([(g.appid, g.bin_dir) for g in find_games(self.steam)], [(FULL, full)])

    def test_finds_demo_and_full_game_in_two_libraries(self):
        demo = self.install(self.steam, DEMO, "Voyager Demo", " Demo")
        full = self.install(self.lib2, FULL, "Voyager")
        games = find_games(self.steam)
        self.assertEqual([(g.appid, g.bin_dir) for g in games], [(FULL, full), (DEMO, demo)])
        self.assertEqual(games[1].name, "Star Trek: Voyager - Across the Unknown Demo")

    def test_listed_but_files_missing_is_not_installed(self):
        (self.steam / "steamapps" / f"appmanifest_{DEMO}.acf").write_text(MANIFEST % (DEMO, "", "Gone"))
        self.assertEqual(find_games(self.steam), [])

    def test_no_steam(self):
        self.assertEqual(find_games(Path(self.tmp.name) / "nowhere"), [])
        self.assertEqual(find_games(None), [])


if __name__ == "__main__":
    unittest.main()
