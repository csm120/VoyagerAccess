import json
import sys
import tempfile
import unittest
import zipfile
import hashlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager import app, modfiles, updater  # noqa: E402

FOUND = ("9.9.9", Path("setup.exe"), Path("Scripts"))


class PlaySessionTests(unittest.TestCase):
    """Update checks while the game runs: early ones restart the game; later
    ones patch the scripts live and offer F12 to restart for the rest."""

    def setUp(self):
        self.saved = app.fetch_update
        self.now = 1000.0
        self.said, self.applied, self.fetches = [], [], 0
        self.result = None

    def tearDown(self):
        app.fetch_update = self.saved

    def session(self):
        def fetch():
            self.fetches += 1
            return self.result
        app.fetch_update = fetch
        return app.PlaySession(clock=lambda: self.now, threads=False)

    def step(self, s):
        def apply(found):
            self.applied.append(found)
            return True
        s.step(self.said.append, apply)

    def test_early_update_restarts_the_game(self):
        self.result = FOUND
        s = self.session()
        self.now += 10
        self.step(s)
        self.assertTrue(s.restart)
        self.assertEqual(self.applied, [])

    def test_late_update_patches_live_and_offers_f12(self):
        s = self.session()
        self.step(s)                         # first check: nothing
        self.result = FOUND
        self.now += app.PLAY_CHECK_SECONDS
        self.step(s)
        self.assertFalse(s.restart)
        self.assertEqual(self.applied, [FOUND])
        # The mod's reload says "Voyager Access loaded", interrupting; the
        # message waits until that is over (heard 2026-10-11).
        self.assertEqual(self.said, [])
        self.now += app.ANNOUNCE_DELAY_SECONDS
        self.step(s)
        self.assertTrue(self.said[-1].startswith("Voyager Access fixes applied."))
        self.step(s)
        self.assertEqual(len(self.said), 1)
        s.key(["f12"])
        self.assertTrue(s.restart)

    def test_release_without_scripts_offers_f12_at_once(self):
        s = self.session()
        self.step(s)
        self.result = FOUND
        self.now += app.PLAY_CHECK_SECONDS
        s.step(self.said.append, lambda found: False)
        self.assertTrue(self.said[-1].startswith("Voyager Access update 9.9.9 is ready."))
        s.key(["f12"])
        self.assertTrue(s.restart)

    def test_checks_again_only_after_the_interval(self):
        s = self.session()
        self.step(s)
        self.now += app.PLAY_CHECK_SECONDS - 1
        self.step(s)
        self.assertEqual(self.fetches, 1)
        self.now += 1
        self.step(s)
        self.assertEqual(self.fetches, 2)

    def test_no_more_checks_once_found(self):
        self.result = FOUND
        s = self.session()
        self.now += app.RESTART_WINDOW_SECONDS + 1
        self.step(s)
        self.now += app.PLAY_CHECK_SECONDS * 3
        self.step(s)
        self.assertEqual(self.fetches, 1)
        self.assertEqual(len(self.applied), 1)

    def test_f12_without_an_update_does_nothing(self):
        s = self.session()
        self.step(s)
        s.key(["f12"])
        self.assertFalse(s.restart)

    def test_f12_without_an_update_checks_now(self):
        # Casey, 2026-10-11: F12 also checks on demand.
        s = self.session()
        self.step(s)
        self.assertEqual(self.fetches, 1)
        s.key(["f12"])
        self.step(s)                         # well before the ten minutes
        self.assertEqual(self.fetches, 2)
        self.assertFalse(s.restart)
        self.assertEqual(self.said[0], "Checking for Voyager Access updates.")
        self.assertTrue(self.said[-1].startswith("Voyager Access is up to date"))
        self.step(s)
        self.assertEqual(len(self.said), 2)

    def test_f12_check_finding_an_update_patches_then_second_f12_restarts(self):
        s = self.session()
        self.now += app.RESTART_WINDOW_SECONDS + 1
        self.step(s)
        self.result = FOUND
        s.key(["f12"])
        self.step(s)
        self.assertFalse(s.restart)
        self.assertEqual(self.applied, [FOUND])
        self.now += app.ANNOUNCE_DELAY_SECONDS
        self.step(s)
        self.assertTrue(self.said[-1].startswith("Voyager Access fixes applied."))
        s.key(["f12"])
        self.assertTrue(s.restart)

    def test_f12_check_that_fails_says_so(self):
        s = self.session()
        self.step(s)

        def broken():
            raise OSError("no network")
        app.fetch_update = broken
        s.key(["f12"])
        self.step(s)
        self.assertEqual(self.said[-1], "Could not check for Voyager Access updates.")

    def test_a_failing_check_does_nothing(self):
        def broken():
            raise OSError("no network")
        app.fetch_update = broken
        s = app.PlaySession(clock=lambda: self.now, threads=False)
        s.step(self.said.append, self.applied.append)
        self.assertFalse(s.restart)
        self.assertEqual(self.said, [])


class PatchScriptsTests(unittest.TestCase):
    def test_new_script_is_copied_and_recorded_for_uninstall(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            payload, game, data, fix = root / "payload", root / "game", root / "data", root / "fix"
            scripts = payload / "ue4ss" / "Mods" / "VoyagerAccess" / "Scripts"
            scripts.mkdir(parents=True)
            (scripts / "main.lua").write_text("old")
            game.mkdir()
            modfiles.install(game, payload, data, "1", game_running=lambda: False, version="1.0")
            fix.mkdir()
            (fix / "main.lua").write_text("new")
            (fix / "extra.lua").write_text("added")
            modfiles.patch_scripts(game, fix, data, "1")
            live = game / "ue4ss" / "Mods" / "VoyagerAccess" / "Scripts"
            self.assertEqual((live / "main.lua").read_text(), "new")
            self.assertEqual((live / "extra.lua").read_text(), "added")
            manifest = modfiles.load_manifest(data, "1")
            self.assertIn("ue4ss/Mods/VoyagerAccess/Scripts/extra.lua", manifest["files"])
            self.assertEqual(manifest["version"], "1.0")   # the full install still runs later
            modfiles.uninstall(game, data, "1", game_running=lambda: False)
            self.assertFalse((live / "extra.lua").exists())


class ModDownloadTests(unittest.TestCase):
    def make(self, root, good=True):
        z = root / "VoyagerAccessMod.zip"
        with zipfile.ZipFile(z, "w") as f:
            f.writestr("Scripts/main.lua", "new")
        digest = hashlib.sha256(z.read_bytes()).hexdigest() if good else "0" * 64
        (root / "VoyagerAccessMod.zip.sha256").write_text(digest + "  VoyagerAccessMod.zip\n")
        assets = [{"name": n, "browser_download_url": (root / n).as_uri()}
                  for n in ("VoyagerAccessSetup.exe", "VoyagerAccessSetup.exe.sha256",
                            "VoyagerAccessMod.zip", "VoyagerAccessMod.zip.sha256")]
        (root / "latest.json").write_text(json.dumps({"tag_name": "v9.9.9", "assets": assets}))
        return updater.check((root / "latest.json").as_uri(), "1.0")

    def test_scripts_are_verified_and_unpacked(self):
        with tempfile.TemporaryDirectory() as tmp:
            release = self.make(Path(tmp))
            scripts = updater.download_scripts(release, Path(tmp) / "out")
            self.assertEqual((scripts / "main.lua").read_text(), "new")

    def test_bad_checksum_gives_no_scripts(self):
        with tempfile.TemporaryDirectory() as tmp:
            release = self.make(Path(tmp), good=False)
            with self.assertRaises(updater.UpdateError):
                updater.download_scripts(release, Path(tmp) / "out")


class RelaunchMarkerTests(unittest.TestCase):
    def test_marker_names_the_game_to_start_again(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "pending-update.json"
            updater.write_marker(marker, "9.9.9", relaunch="4054540")
            self.assertEqual(updater.relaunch_target(marker), "4054540")
            self.assertEqual(updater.read_marker(marker, "9.9.9"), "updated")
            self.assertIsNone(updater.relaunch_target(marker))

    def test_plain_marker_starts_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "pending-update.json"
            updater.write_marker(marker, "9.9.9")
            self.assertIsNone(updater.relaunch_target(marker))


class LaunchModeTests(unittest.TestCase):
    """Steam runs '"VoyagerAccess.exe" --launch %command% -dx11'."""

    def test_launch_passes_the_whole_game_command(self):
        saved = app.launch_game, app.setup_logging
        got = []
        app.launch_game = lambda cmd: got.append(cmd) or 0
        app.setup_logging = lambda: None
        try:
            app.main(["--launch", r"C:\Games\STVoyager.exe", "-dx11", "--some-flag"])
        finally:
            app.launch_game, app.setup_logging = saved
        self.assertEqual(got, [[r"C:\Games\STVoyager.exe", "-dx11", "--some-flag"]])

    def test_no_arguments_is_the_after_install_run(self):
        saved = app.post_install, app.setup_logging
        called = []
        app.post_install = lambda: called.append(True) or 0
        app.setup_logging = lambda: None
        try:
            app.main([])
        finally:
            app.post_install, app.setup_logging = saved
        self.assertEqual(called, [True])

    def test_launch_empties_the_speech_file_before_the_game_starts(self):
        # "Voyager Access loaded" was missed when the last session left a
        # short speech file: the reader started past the mod's first line.
        import subprocess
        saved = (app.DEFAULT_FILE, subprocess.Popen, app.single_instance, app.keep_installed)
        seen = []
        with tempfile.TemporaryDirectory() as d:
            speech = Path(d) / "speech.txt"
            speech.write_text("I|old\n")
            app.DEFAULT_FILE = speech
            subprocess.Popen = lambda cmd: seen.append(speech.read_text())
            app.single_instance = lambda: False      # second copy: start the game and return
            app.keep_installed = lambda: None
            try:
                app.launch_game(["game.exe"])
            finally:
                app.DEFAULT_FILE, subprocess.Popen, app.single_instance, app.keep_installed = saved
        self.assertEqual(seen, [""])

    def test_development_run_never_points_steam_at_python(self):
        self.assertIsNone(app.helper_exe())

    def test_clear_relaunch_keeps_the_expected_version(self):
        with tempfile.TemporaryDirectory() as d:
            m = Path(d) / "pending-update.json"
            updater.write_marker(m, "9.9.9", relaunch="4054540")
            updater.clear_relaunch(m)
            self.assertIsNone(updater.relaunch_target(m))
            self.assertEqual(json.loads(m.read_text())["expected"], "9.9.9")


class SteamRestartTests(unittest.TestCase):
    """Casey, 2026-10-11: the player should not have to answer anything.
    Steam restarts by itself unless another game is running through it."""

    def test_steam_closed_means_edit_at_once(self):
        self.assertEqual(app.steam_restart_plan(steam_on=False, game_running=False), "edit")

    def test_idle_steam_restarts_without_asking(self):
        self.assertEqual(app.steam_restart_plan(steam_on=True, game_running=False), "restart")

    def test_a_running_game_is_waited_for(self):
        self.assertEqual(app.steam_restart_plan(steam_on=True, game_running=True), "wait")


class ReportTests(unittest.TestCase):
    """Backtick copies a report for Casey (2026-10-11): version, launch
    options, the helper's log and the mod's lines from the game log."""

    def test_report_has_each_part(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "helper.log").write_text("line one\nline two\n", encoding="utf-8")
            game_log = d / "UE4SS.log"
            game_log.write_text("[x] other\n[x] [Lua] [VoyagerAccess] course: under way\n", encoding="utf-8")
            cfg = d / "localconfig.vdf"
            cfg.write_text('"LaunchOptions"\t\t"\\"C:\\\\VoyagerAccess.exe\\" --launch %command% -dx11"\n',
                           encoding="utf-8")
            text = app.build_report(d / "helper.log", [game_log], [cfg])
        self.assertIn(app.__version__, text)
        self.assertIn("--launch %command% -dx11", text)
        self.assertIn("line two", text)
        self.assertIn("course: under way", text)
        self.assertNotIn("other", text)

    def test_backtick_is_watched(self):
        from voyager.helper import VK
        self.assertEqual(VK["grave"], 0xC0)


class UpdateNewsTests(unittest.TestCase):
    def test_update_news_names_ctrl_f12(self):
        # Casey, 2026-10-11: when the version is spoken, say Ctrl+F12 for what's new.
        saved = app.UPDATE_MARKER
        with tempfile.TemporaryDirectory() as d:
            app.UPDATE_MARKER = Path(d) / "pending-update.json"
            try:
                updater.write_marker(app.UPDATE_MARKER, app.__version__)
                news = app.update_news()
            finally:
                app.UPDATE_MARKER = saved
        self.assertIn(app.__version__, news)
        self.assertIn("Ctrl+F12", news)


class InGameUpdateTests(unittest.TestCase):
    """2026-10-11: the update-reload flag froze the game twice in four
    tries, so an update found during play must not reload the mod."""

    def test_in_game_update_does_not_reload_the_mod(self):
        saved = app.RELOAD_FLAG
        with tempfile.TemporaryDirectory() as d:
            app.RELOAD_FLAG = Path(d) / "reload"
            try:
                self.assertFalse(app.apply_in_game(FOUND))
                self.assertFalse(app.RELOAD_FLAG.exists())
            finally:
                app.RELOAD_FLAG = saved


if __name__ == "__main__":
    unittest.main()
