"""Uninstall must not leave Steam pointing at a deleted VoyagerAccess.exe
(Fable review, 2026-11-10, helper finding 2)."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager import app, launchopts, modfiles  # noqa: E402
from tests.test_launchopts import BASE, DEMO_WITH  # noqa: E402

EXE = r"C:\Program Files\Voyager Access\VoyagerAccess.exe"


class UninstallLaunchOptionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.cfg = root / "steam" / "userdata" / "1" / "config" / "localconfig.vdf"
        self.cfg.parent.mkdir(parents=True)
        self.saved = (app.steam.steam_path, app.helper_exe, app.LAUNCH_RECORD,
                      app.steam_running, app.steam_game_running, app.message,
                      app.DATA_DIR, modfiles.uninstall_all, modfiles.game_is_running)
        modfiles.game_is_running = lambda: False
        app.steam.steam_path = lambda: root / "steam"
        app.helper_exe = lambda: EXE
        app.LAUNCH_RECORD = root / "data" / "launch-options.json"
        app.steam_running = lambda: False
        app.steam_game_running = lambda: False
        self.answers = []
        app.message = lambda text, flags=0: self.answers.pop(0) if self.answers else 6
        app.DATA_DIR = root / "data"

    def tearDown(self):
        (app.steam.steam_path, app.helper_exe, app.LAUNCH_RECORD,
         app.steam_running, app.steam_game_running, app.message,
         app.DATA_DIR, modfiles.uninstall_all, modfiles.game_is_running) = self.saved
        self.tmp.cleanup()

    def write(self, options):
        self.cfg.write_bytes((BASE % (DEMO_WITH % launchopts.escape(options))).encode("utf-8"))

    def options(self):
        return launchopts.unescape(launchopts.get_option(launchopts.read_file(self.cfg), "4054540"))

    def test_wrapper_without_a_record_is_still_removed(self):
        # A reinstall over an existing wrapper writes no record (set_launch_options
        # returns early), so the record cannot be what uninstall relies on.
        self.write('"%s" --launch %%command%% -dx11 -windowed' % EXE)
        self.assertTrue(app.unset_launch_options())
        self.assertEqual(self.options(), "-dx11 -windowed")

    def test_wrapper_around_the_players_own_command_keeps_it(self):
        self.write('PROTON_LOG=1 "%s" --launch %%command%% -windowed' % EXE)
        self.assertTrue(app.unset_launch_options())
        self.assertEqual(self.options(), "PROTON_LOG=1 %command% -windowed")

    def test_another_programs_wrapper_is_left_alone(self):
        # Negative twin: only this exe's own wrapper is removed.
        other = '"C:\\Other\\Tool.exe" --launch %command% -dx11'
        self.write(other)
        self.assertTrue(app.unset_launch_options())
        self.assertEqual(self.options(), other)

    def test_steam_restart_refused_is_reported(self):
        self.write('"%s" --launch %%command%%' % EXE)
        app.steam_running = lambda: True
        app.steam_game_running = lambda: True
        self.answers = [7]     # No
        self.assertFalse(app.unset_launch_options())
        self.assertIn("--launch", self.options())

    def test_uninstall_mod_fails_when_launch_options_stay(self):
        self.write('"%s" --launch %%command%%' % EXE)
        app.steam_running = lambda: True
        app.steam_game_running = lambda: True
        modfiles.uninstall_all = lambda data_dir, game_running=None: None
        self.answers = [7]
        self.assertNotEqual(app.uninstall_mod(), 0)

    def test_uninstall_mod_file_error_still_unwraps_and_fails(self):
        self.write('"%s" --launch %%command%%' % EXE)

        def broken(data_dir, game_running=None):
            raise PermissionError("locked")
        modfiles.uninstall_all = broken
        self.assertNotEqual(app.uninstall_mod(), 0)
        self.assertNotIn("--launch", self.options() or "")

    def test_clean_uninstall_succeeds(self):
        self.write('"%s" --launch %%command%%' % EXE)
        modfiles.uninstall_all = lambda data_dir, game_running=None: None
        self.assertEqual(app.uninstall_mod(), 0)
        self.assertFalse(self.options())

    # Pre-merge review 2026-11-10, M2: the uninstaller stops on any failed
    # --uninstall-mod, so a failure that is the same on every try must say
    # so with its own exit code (setup then offers to uninstall anyway),
    # apart from the player's own choice to stop (exit 1, setup stops).

    def test_steam_gone_with_a_record_still_finishes(self):
        # Steam uninstalled after the launch options were set: steam_path()
        # is None and _restart_steam(None, ...) raised TypeError every time.
        class G:
            appid = "4054540"
        self.write("-windowed")
        app.set_launch_options([G()])
        self.assertTrue(app.LAUNCH_RECORD.exists())
        app.steam.steam_path = lambda: None
        self.assertTrue(app.unset_launch_options())
        self.assertFalse(app.LAUNCH_RECORD.exists())
        self.assertEqual(self.options(), "-windowed")

    def test_file_error_is_told_apart_from_the_players_choice(self):
        self.write('"%s" --launch %%command%%' % EXE)

        def broken(data_dir, game_running=None):
            raise FileNotFoundError("game folder gone")
        modfiles.uninstall_all = broken
        self.assertEqual(app.uninstall_mod(), app.UNINSTALL_ERROR)

    def test_unexpected_error_is_an_uninstall_error_not_a_crash(self):
        def broken(data_dir, game_running=None):
            raise RuntimeError("anything else")
        modfiles.uninstall_all = broken
        self.assertEqual(app.uninstall_mod(), app.UNINSTALL_ERROR)

    # Codex release review 2026-11-11, finding 1: an edit that failed while
    # Steam was closed was logged and dropped, the record was deleted, and
    # uninstall exited 0, so setup deleted the exe Steam still starts.
    def test_failed_edit_keeps_the_record_and_fails(self):
        class G:
            appid = "4054540"
        self.write("-windowed")
        app.set_launch_options([G()])
        self.assertTrue(app.LAUNCH_RECORD.exists())
        saved = launchopts.edit_file

        def locked(f, change):
            raise PermissionError("locked")
        launchopts.edit_file = locked
        try:
            self.assertFalse(app.unset_launch_options())
        finally:
            launchopts.edit_file = saved
        self.assertTrue(app.LAUNCH_RECORD.exists())
        self.assertIn("--launch", self.options())
        # The record still undoes it on the next try.
        self.assertTrue(app.unset_launch_options())
        self.assertEqual(self.options(), "-windowed")

    # Fable release review 2026-11-11, high 1: after 005f63b every OSError
    # kept the record, so a recorded file that no longer exists (Steam or a
    # Steam account removed after install) failed every uninstall for ever.
    # A file that is not there has nothing of ours left in it.
    def record_wrap(self):
        class G:
            appid = "4054540"
        self.write("-windowed")
        app.set_launch_options([G()])
        self.assertTrue(app.LAUNCH_RECORD.exists())

    def test_recorded_file_gone_is_done_not_failed(self):
        import shutil
        self.record_wrap()
        shutil.rmtree(self.cfg.parent.parent)          # the account's userdata folder
        self.assertTrue(app.unset_launch_options())
        self.assertFalse(app.LAUNCH_RECORD.exists())

    def test_steam_gone_and_its_folder_gone_still_finishes(self):
        import shutil
        self.record_wrap()
        shutil.rmtree(self.cfg.parent.parent.parent.parent)   # the whole steam folder
        app.steam.steam_path = lambda: None
        modfiles.uninstall_all = lambda data_dir, game_running=None: None
        self.assertEqual(app.uninstall_mod(), 0)
        self.assertFalse(app.LAUNCH_RECORD.exists())

    def test_unrecorded_file_gone_between_scan_and_edit_is_done(self):
        self.write('"%s" --launch %%command%%' % EXE)
        saved = launchopts.edit_file

        def gone(f, change):
            raise FileNotFoundError(str(f))
        launchopts.edit_file = gone
        try:
            self.assertTrue(app.unset_launch_options())
        finally:
            launchopts.edit_file = saved

    # Fable release review 2026-11-11, medium 2: a failed edit that repeats
    # (localconfig.vdf set read-only) got setup's "close the game and try
    # again", which cannot help. It now has its own exit code and a message
    # naming the file; the uninstall still stops, because the wrapper stays.
    def test_read_only_file_names_the_file_and_has_its_own_exit_code(self):
        import os
        import stat
        self.record_wrap()
        shown = []
        app.message = lambda text, flags=0: shown.append(text) or 1
        calls = []
        modfiles.uninstall_all = lambda data_dir, game_running=None: calls.append(1)
        os.chmod(self.cfg, stat.S_IREAD)
        try:
            code = app.uninstall_mod()
        finally:
            os.chmod(self.cfg, stat.S_IREAD | stat.S_IWRITE)
        self.assertEqual(code, app.LAUNCH_FILE_ERROR)
        self.assertNotIn(code, (0, 1, app.UNINSTALL_ERROR))
        self.assertTrue(any(str(self.cfg) in t and "read-only" in t for t in shown), shown)
        self.assertEqual(calls, [])                       # the mod's files stay
        self.assertTrue(app.LAUNCH_RECORD.exists())
        self.assertIn("--launch", self.options())

    def test_steam_refusal_is_still_exit_1_not_the_file_error(self):
        # Negative twin: a stop the player can clear keeps exit 1.
        self.record_wrap()
        app.steam_running = lambda: True
        app.steam_game_running = lambda: True
        self.answers = [7]     # No
        self.assertEqual(app.uninstall_mod(), 1)

    def test_setup_handles_the_file_error_without_the_close_the_game_box(self):
        iss = (Path(__file__).resolve().parent.parent / "installer" / "VoyagerAccess.iss").read_text(encoding="utf-8")
        branch = iss.find("ResultCode = %d then" % app.LAUNCH_FILE_ERROR)
        generic = iss.find("else if ResultCode <> 0 then")
        self.assertGreaterEqual(branch, 0, "VoyagerAccess.iss has no branch for the file error")
        self.assertLess(branch, generic)
        self.assertIn("Abort;", iss[branch:generic])
        self.assertNotIn("Close the game", iss[branch:generic])

    def test_failed_unrecorded_unwrap_fails_the_uninstall(self):
        self.write('"%s" --launch %%command%%' % EXE)
        modfiles.uninstall_all = lambda data_dir, game_running=None: None
        saved = launchopts.edit_file

        def locked(f, change):
            raise PermissionError("locked")
        launchopts.edit_file = locked
        try:
            self.assertNotEqual(app.uninstall_mod(), 0)
        finally:
            launchopts.edit_file = saved

    # Codex release review 2026-11-11, finding 3: the mod's files were taken
    # out before the Steam question, so answering No stopped the uninstall
    # after the mod was already gone, while setup said nothing was uninstalled.
    def test_steam_refused_leaves_the_mod_files_alone(self):
        self.write('"%s" --launch %%command%%' % EXE)
        app.steam_running = lambda: True
        app.steam_game_running = lambda: True
        calls = []
        modfiles.uninstall_all = lambda data_dir, game_running=None: calls.append(1)
        self.answers = [7]     # No
        self.assertEqual(app.uninstall_mod(), 1)
        self.assertEqual(calls, [])

    def test_steam_restarted_removes_the_mod_files(self):
        # Negative twin: with Steam's restart allowed, the files still go.
        self.write('"%s" --launch %%command%%' % EXE)
        app.steam_running = lambda: False
        calls = []
        modfiles.uninstall_all = lambda data_dir, game_running=None: calls.append(1)
        self.assertEqual(app.uninstall_mod(), 0)
        self.assertEqual(calls, [1])

    def test_game_left_running_still_stops_the_uninstall(self):
        # Negative twin: the player choosing Cancel over a running game is
        # exit 1, which setup still refuses on.
        def running(data_dir, game_running=None):
            raise modfiles.GameRunning()
        modfiles.uninstall_all = running
        self.answers = [2]     # Cancel
        self.assertEqual(app.uninstall_mod(), 1)
        self.assertNotEqual(app.UNINSTALL_ERROR, 1)


class LaunchEditErrorTests(unittest.TestCase):
    """Fable review 2026-11-10, helper finding 5: one localconfig.vdf that
    cannot be edited left Steam closed and wrote no record at all."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.good = root / "steam" / "userdata" / "1" / "config" / "localconfig.vdf"
        self.bad = root / "steam" / "userdata" / "2" / "config" / "localconfig.vdf"
        for f in (self.good, self.bad):
            f.parent.mkdir(parents=True)
        from tests.test_launchopts import DEMO_WITHOUT
        self.good.write_bytes((BASE % DEMO_WITHOUT).encode("utf-8"))
        # An account that never ran a game: no Software/Valve/Steam/apps block.
        self.bad.write_bytes(b'"UserLocalConfigStore"\n{\n}\n')
        import subprocess
        self.saved = (app.steam.steam_path, app.helper_exe, app.LAUNCH_RECORD, app.steam_running,
                      app.steam_game_running, app.time.sleep, subprocess.Popen)
        self.popen = []
        self.steam_on = [True]
        app.steam.steam_path = lambda: root / "steam"
        app.helper_exe = lambda: EXE
        app.LAUNCH_RECORD = root / "data" / "launch-options.json"
        app.steam_running = lambda: self.steam_on[0]
        app.steam_game_running = lambda: False
        app.time.sleep = lambda s: None

        def popen(args, *a, **k):
            self.popen.append(list(args))
            if "-shutdown" in args:
                self.steam_on[0] = False
        subprocess.Popen = popen

    def tearDown(self):
        import subprocess
        (app.steam.steam_path, app.helper_exe, app.LAUNCH_RECORD, app.steam_running,
         app.steam_game_running, app.time.sleep, subprocess.Popen) = self.saved
        self.tmp.cleanup()

    def games(self):
        class G:
            appid = "4054540"
        return [G()]

    def test_bad_file_still_restarts_steam_and_records_the_good_one(self):
        app.set_launch_options(self.games())
        self.assertTrue(any("-silent" in c for c in self.popen), self.popen)
        record = json.loads(app.LAUNCH_RECORD.read_text(encoding="utf-8"))
        self.assertTrue(any(e["file"] == str(self.good) and e.get("kind") == "wrap" for e in record))
        self.assertIn("--launch", launchopts.unescape(
            launchopts.get_option(launchopts.read_file(self.good), "4054540")))


class AtomicEditTests(unittest.TestCase):
    """Fable review 2026-11-10, helper low 8: localconfig.vdf was truncated
    and rewritten in place, so a failure part way lost the account's
    settings for every game."""

    def test_failed_write_leaves_the_file_whole(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "localconfig.vdf"
            f.write_bytes(b"original settings")
            real = Path.write_bytes

            def half(self, data):
                if self.name == "localconfig.vdf" or self.parent == f.parent:
                    real(self, data[:3])
                    raise OSError("disk full")
                return real(self, data)
            Path.write_bytes = half
            try:
                with self.assertRaises(OSError):
                    launchopts.edit_file(f, lambda t: t + " plus more")
            finally:
                Path.write_bytes = real
            self.assertEqual(f.read_bytes(), b"original settings")
            self.assertEqual(sorted(p.name for p in Path(d).iterdir()), ["localconfig.vdf"])

    def test_edit_still_changes_the_file(self):
        # Negative twin.
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "localconfig.vdf"
            f.write_bytes(b"a\nb\n")
            self.assertTrue(launchopts.edit_file(f, lambda t: t + "c\n"))
            self.assertEqual(f.read_bytes(), b"a\nb\nc\n")


class ClosedDuringNoticeTests(unittest.TestCase):
    """Pre-merge review 2026-11-10, L5: close_game returns None both when the
    game stayed open and when it was already gone (the player closed it
    during the five second notice), and the helper then said "The game did
    not close" to a closed game."""

    def setUp(self):
        self.saved = (app.modfiles.close_game, app.modfiles.game_is_running, app.install_update,
                      app.time.sleep)
        self.installed = []
        app.modfiles.close_game = lambda timeout=90: None
        app.install_update = lambda v, p, relaunch=None: self.installed.append((v, relaunch))
        app.time.sleep = lambda s: None

        class Speech:
            def say(self, text, interrupt=False):
                pass
        self.tolk = Speech()

    def tearDown(self):
        (app.modfiles.close_game, app.modfiles.game_is_running, app.install_update,
         app.time.sleep) = self.saved

    def test_game_closed_by_the_player_installs_now(self):
        app.modfiles.game_is_running = lambda: False
        self.assertTrue(app.restart_for_update(self.tolk, ("9.9.9", Path("setup.exe")), False))
        self.assertEqual(self.installed, [("9.9.9", None)])

    def test_game_still_open_waits(self):
        # Negative twin: a game that really stayed open is still waited for.
        app.modfiles.game_is_running = lambda: True
        self.assertFalse(app.restart_for_update(self.tolk, ("9.9.9", Path("setup.exe")), False))
        self.assertEqual(self.installed, [])


class GameWouldNotCloseTests(unittest.TestCase):
    """Fable review 2026-11-10, helper finding 4: when the game would not
    close for an update, the helper unloaded speech and exited with the
    game still running."""

    def setUp(self):
        self.saved = (app.PlaySession, app.open_speech, app.HeartbeatWatch, app.serve,
                      app.restart_for_update, app.install_update, app.RELOAD_FLAG)
        self.events = []
        events = self.events

        class Session:
            found = ("9.9.9", Path("setup.exe"), None)
            early = False
            restart = True

            def step(self, say, apply):
                pass

            def key(self, names):
                pass

            def wait(self):
                pass
        self.session = Session()

        class Speech:
            def say(self, text, interrupt=False):
                events.append(("say", text))

            def unload(self):
                events.append(("unload",))

        class Beat:
            longest = 0.0
            armed = False

            def check(self, say):
                pass
        app.PlaySession = lambda **kwargs: self.session
        app.open_speech = lambda path: Speech()
        app.HeartbeatWatch = Beat
        app.serve = lambda tolk, f, keep_going, on_keys=None: events.append(("serve",))
        app.restart_for_update = lambda tolk, found, early: events.append(("restart",)) or False
        app.install_update = lambda v, p, relaunch=None: events.append(("install",))
        app.RELOAD_FLAG = Path(tempfile.gettempdir()) / "voyager-test-no-such-reload-flag"

    def tearDown(self):
        (app.PlaySession, app.open_speech, app.HeartbeatWatch, app.serve,
         app.restart_for_update, app.install_update, app.RELOAD_FLAG) = self.saved

    def test_speech_goes_on_until_the_game_closes(self):
        app.play_session()
        kinds = [e[0] for e in self.events]
        # serve, failed restart, said so, serve again; unload only after that.
        self.assertEqual(kinds.count("serve"), 2, kinds)
        self.assertLess(kinds.index("restart"), len(kinds) - 1 - kinds[::-1].index("serve"))
        self.assertGreater(kinds.index("unload"), len(kinds) - 1 - kinds[::-1].index("serve"))
        said = " ".join(e[1] for e in self.events if e[0] == "say")
        self.assertIn("did not close", said)
        self.assertEqual(kinds[-1], "install")

    def test_a_restart_that_works_ends_at_once(self):
        # Negative twin: a game that closed still hands over to setup.
        app.restart_for_update = lambda tolk, found, early: self.events.append(("restart",)) or True
        self.assertEqual(app.play_session(), 0)
        kinds = [e[0] for e in self.events]
        self.assertEqual(kinds.count("serve"), 1)
        self.assertNotIn("install", kinds)


if __name__ == "__main__":
    unittest.main()
