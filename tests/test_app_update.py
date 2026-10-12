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
