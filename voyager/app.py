"""Voyager Access: the program the installer puts on the computer.

    VoyagerAccess.exe --launch CMD...   Steam runs this in place of the game (the
                                        game's launch options): put the mod in if
                                        needed, start CMD (the game), speak and check
                                        for updates while it runs, exit with it
    VoyagerAccess.exe                   what setup runs after installing: put the
                                        mod in, set the launch options if missing,
                                        start the game again after an update, exit
    VoyagerAccess.exe --install-mod     put the mod into the game, then start it
    VoyagerAccess.exe --uninstall-mod   take it out of every game it was put in
    VoyagerAccess.exe --start-game      start the game through Steam (setup's Finish)
    VoyagerAccess.exe --speech-check F  write a report on the bundled files to F

Nothing runs at Windows sign-in (Casey, 2026-10-11): the helper starts with
the game and ends with it. Before starting the game it puts the mod back if
an update or Steam's file check removed it.
"""
import argparse
import ctypes
import logging
import logging.handlers
import os
import sys
import threading
import time
from pathlib import Path
from typing import NamedTuple, Optional

from . import modfiles, steam, updater
from .helper import DATA_DIR, DEFAULT_FILE, DEFAULT_TOLK, RESOURCES, HeartbeatWatch, Tolk, open_speech, serve
from .version import __version__

PAYLOAD = RESOURCES / "payload"
TITLE = "Voyager Access"
GAME = "Star Trek: Voyager - Across the Unknown"

log = logging.getLogger("voyager")

MB_OK, MB_YESNOCANCEL, MB_YESNO, MB_RETRYCANCEL = 0x0, 0x3, 0x4, 0x5
MB_ICONINFORMATION, MB_ICONWARNING, MB_ICONQUESTION = 0x40, 0x30, 0x20
IDYES, IDNO, IDRETRY = 6, 7, 4


def message(text, flags=MB_OK | MB_ICONINFORMATION):
    """A standard Windows message box; screen readers read it in full."""
    return ctypes.windll.user32.MessageBoxW(None, text, TITLE, flags | 0x10000)  # MB_SETFOREGROUND


def setup_logging():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    handler = logging.handlers.RotatingFileHandler(DATA_DIR / "helper.log", maxBytes=200_000,
                                                   backupCount=1, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
    log.addHandler(handler)
    log.setLevel(logging.INFO)
    # An uncaught exception on any thread goes to helper.log: the frozen exe
    # has no console, and a crash that ended speech left no trace before
    # 2026-10-29 (the WFH session's reliability review).
    old_hook = sys.excepthook

    def crash(kind, value, tb):
        log.error("uncaught exception", exc_info=(kind, value, tb))
        old_hook(kind, value, tb)

    def thread_crash(args):
        log.error("uncaught exception in thread %s", getattr(args.thread, "name", "?"),
                  exc_info=(args.exc_type, args.exc_value, args.exc_traceback))

    sys.excepthook = crash
    threading.excepthook = thread_crash


def needs_install(game):
    manifest = modfiles.load_manifest(DATA_DIR, game.appid)
    return manifest is None or manifest.get("version") != __version__ \
        or not (game.bin_dir / "dwmapi.dll").is_file()


def install_into(game):
    modfiles.install(game.bin_dir, PAYLOAD, DATA_DIR, game.appid, version=__version__)
    log.info("installed %s into %s", __version__, game.bin_dir)


def keep_installed():
    """Quietly installs or updates the mod in every copy of the game."""
    for game in steam.find_games(steam.steam_path()):
        if needs_install(game):
            try:
                install_into(game)
            except modfiles.GameRunning:
                return
            except OSError as e:
                log.info("install into %s failed: %s", game.bin_dir, e)


DX11 = "-dx11"
LAUNCH_RECORD = DATA_DIR / "launch-options.json"


def steam_running():
    return any(p.lower() == "steam.exe" for p in _process_names())


def _process_names():
    import subprocess
    out = subprocess.run(["tasklist", "/fo", "csv", "/nh"], capture_output=True, text=True,
                         creationflags=0x08000000).stdout  # CREATE_NO_WINDOW
    return [line.split('","')[0].strip('"') for line in out.splitlines() if line]


def _restart_steam(steam_dir, edit):
    """Closes Steam, runs edit(), and starts Steam again. Steam rewrites its
    settings file while it runs, so the file is only edited while it is
    closed."""
    import subprocess
    if steam_dir is None:
        # Steam was uninstalled (its registry key is gone) after the launch
        # options were set: nothing to close, and Path(None) failed every
        # uninstall (pre-merge review, 2026-11-10). The recorded files are
        # still edited if they are there.
        edit()
        return True
    exe = Path(steam_dir) / "steam.exe"
    was_running = steam_running()
    if was_running:
        subprocess.Popen([str(exe), "-shutdown"])
        for _ in range(60):
            time.sleep(1)
            if not steam_running():
                break
        else:
            return False
        time.sleep(2)
    try:
        edit()
    finally:
        # Steam is started again whatever the edit did (Fable review,
        # 2026-11-10: one bad file left it closed).
        if was_running:
            subprocess.Popen([str(exe), "-silent"])
    return True


def _load_launch_record():
    import json
    try:
        return json.loads(LAUNCH_RECORD.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []


def helper_exe():
    """This program's own path when installed (a PyInstaller build), else
    None: a development run must not point Steam at python.exe."""
    return str(Path(sys.executable)) if getattr(sys, "frozen", False) else None


def _needs_launch_edit(games, dx11):
    from . import launchopts
    exe = helper_exe()
    todo = []
    for f in launchopts.config_files(steam.steam_path()):
        text = launchopts.read_file(f)
        for g in games:
            current = launchopts.unescape(launchopts.get_option(text, g.appid)) or ""
            wrap = exe is not None and ('"%s" --launch ' % exe) not in current
            add_dx11 = dx11 and DX11 not in current.split()
            if wrap or add_dx11:
                todo.append((f, g.appid, add_dx11, wrap))
    return todo


def steam_game_running():
    """True while Steam is running a game: Steam keeps its app id in
    HKCU\\Software\\Valve\\Steam\\RunningAppID (0 when none)."""
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam") as k:
            return int(winreg.QueryValueEx(k, "RunningAppID")[0]) != 0
    except (OSError, ValueError):
        return False


def steam_restart_plan(steam_on, game_running):
    """No question for the player (Casey, 2026-10-11): edit at once when
    Steam is closed, restart it when it is idle, and wait while it runs a
    game, so nobody's game is cut off."""
    if not steam_on:
        return "edit"
    return "wait" if game_running else "restart"


WAIT_POLL_SECONDS = 30
WAIT_LIMIT_SECONDS = 12 * 3600
RUN_ONCE = r"Software\Microsoft\Windows\CurrentVersion\RunOnce"


def _run_once(on):
    """A one-time sign-in entry that finishes this setup if the computer is
    shut down while waiting; Windows deletes it when it runs."""
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_ONCE, 0, winreg.KEY_SET_VALUE) as k:
            if on and helper_exe():
                winreg.SetValueEx(k, TITLE, 0, winreg.REG_SZ, '"%s"' % helper_exe())
            else:
                winreg.DeleteValue(k, TITLE)
    except OSError:
        pass


def set_launch_options(games, dx11=True):
    """Sets each game's Steam launch options so Steam starts this helper,
    which starts the game (nothing runs at Windows sign-in; Casey,
    2026-10-11), and adds -dx11 (the game crashed under DirectX 12 on
    Casey's computer, 2026-10-10). Steam has to be closed while its file
    is edited. What is added is recorded, so uninstall removes only that.
    Nothing is asked: see steam_restart_plan. Returns False when Steam
    would not close or a game kept running past the wait limit."""
    import json
    from . import launchopts
    todo = _needs_launch_edit(games, dx11)
    if not todo:
        return True
    if steam_restart_plan(steam_running(), steam_game_running()) == "wait":
        log.info("a game is running in Steam; waiting to set the launch options")
        _run_once(True)
        waited = 0
        while steam_running() and steam_game_running():
            if waited >= WAIT_LIMIT_SECONDS:
                log.info("still running after the wait limit; finishing at the next sign-in")
                return False
            time.sleep(WAIT_POLL_SECONDS)
            waited += WAIT_POLL_SECONDS
        _run_once(False)
    record = _load_launch_record()
    exe = helper_exe()

    def edit():
        for f, appid, add_dx11, wrap in todo:
            # One account's file that cannot be read, written or parsed (an
            # account that never ran a game has no apps block) is logged and
            # skipped; the others are still edited and recorded.
            try:
                edit_one(f, appid, add_dx11, wrap)
            except (OSError, ValueError) as e:
                log.info("launch options for %s in %s not set: %s", appid, f, e)

    def edit_one(f, appid, add_dx11, wrap):
        if add_dx11:
            created = launchopts.get_option(launchopts.read_file(f), appid) is None
            if launchopts.edit_file(f, lambda t: launchopts.add_option(t, appid, DX11)):
                record.append({"file": str(f), "appid": appid, "created": created})
                log.info("added %s for %s in %s", DX11, appid, f)
        if wrap:
            info = {}

            def change(t):
                new, i = launchopts.wrap_launch(t, appid, exe)
                if i:
                    info.update(i)
                return new
            if launchopts.edit_file(f, change):
                record.append(dict(kind="wrap", file=str(f), appid=appid, exe=exe, **info))
                log.info("launch options for %s in %s now start Voyager Access", appid, f)

    def save_record():
        LAUNCH_RECORD.parent.mkdir(parents=True, exist_ok=True)
        LAUNCH_RECORD.write_text(json.dumps(record, indent=1), encoding="utf-8")

    try:
        closed = _restart_steam(steam.steam_path(), edit)
    finally:
        # Whatever was changed is recorded, even if the edit stopped part
        # way, so uninstall can undo it.
        if record:
            try:
                save_record()
            except OSError as e:
                log.info("could not save the launch options record: %s", e)
    if closed:
        return True
    log.info("Steam did not close; launch options not set")
    return False


def unset_launch_options(failed_files=None):
    """Removes what set_launch_options added (the wrapper and -dx11), and
    nothing else. True when nothing of ours is left in Steam's launch
    options; False when Steam could not be closed for the edit, or an edit
    failed, so the uninstaller stops before it deletes the exe the options
    still start. Each file whose edit failed is added to failed_files.

    The record is not needed to find the wrapper (Fable review,
    2026-11-10): a reinstall over an existing wrapper writes no record, so
    any '"<this exe>" --launch ' left in an account's file is unwrapped too.
    Only -dx11 needs the record (it cannot be told from the player's own)."""
    from . import launchopts
    record = _load_launch_record()
    exe = helper_exe()
    leftover = []
    if exe:
        recorded = {(e.get("file"), str(e.get("appid"))) for e in record if e.get("kind") == "wrap"}
        for f in launchopts.config_files(steam.steam_path()):
            try:
                text = launchopts.read_file(f)
            except OSError:
                continue
            for appid in (steam.FULL, steam.DEMO):
                current = launchopts.unescape(launchopts.get_option(text, appid)) or ""
                if (str(f), appid) not in recorded and ('"%s" --launch ' % exe) in current:
                    leftover.append((f, appid, current))
    if not record and not leftover:
        return True
    # Uninstall has to finish now, so it asks only when closing Steam would
    # cut off a game that is running.
    if steam_restart_plan(steam_running(), steam_game_running()) == "wait" and message(
            "Voyager Access changed the game's launch options in Steam. To put them back, Steam has to "
            "close for a moment and start again, and a game is running in Steam now.\n\n"
            "Close and restart Steam now?",
            MB_YESNOCANCEL | MB_ICONQUESTION) != IDYES:
        return False

    # An edit that fails here leaves Steam starting this exe, so it must fail
    # the uninstall and keep its record for the next try (Codex release
    # review, 2026-11-11: it was logged and dropped, the record deleted, and
    # setup then deleted the exe). Unrecorded wrappers are found again by
    # the scan above, so they need no record.
    failed = []
    failed_paths = []

    def edit():
        # Wrappers with no record: had the options their own %command%?
        # wrap_launch put the wrapper at the very start when they had not.
        for f, appid, current in leftover:
            rest = current.replace('"%s" --launch ' % exe, "", 1)
            info = {"had_command": not current.startswith('"%s" --launch ' % exe), "created": True}
            try:
                launchopts.edit_file(f, lambda t: launchopts.unwrap_launch(t, appid, exe, info))
                log.info("removed an unrecorded wrapper for %s in %s (%s left)", appid, f, rest)
            except FileNotFoundError:
                # Gone since the scan: nothing of ours is left in it.
                log.info("%s is gone; nothing to unwrap", f)
            except (OSError, ValueError) as e:
                log.info("could not unwrap %s in %s: %s", appid, f, e)
                failed.append(None)
                failed_paths.append(str(f))
        # Newest first, so each edit is undone on the text it produced.
        for entry in reversed(record):
            f = Path(entry["file"])
            try:
                if entry.get("kind") == "wrap":
                    launchopts.edit_file(f, lambda t: launchopts.unwrap_launch(
                        t, entry["appid"], entry["exe"], entry))
                else:
                    launchopts.edit_file(f, lambda t: launchopts.remove_option(
                        t, entry["appid"], DX11, drop_empty=entry.get("created", False)))
            except FileNotFoundError:
                # Steam, or that Steam account, was removed after install: a
                # file that is not there starts nothing, so this edit is done
                # (Fable release review, 2026-11-11: kept as failed, it
                # blocked every uninstall for ever).
                log.info("%s is gone; nothing to put back", f)
            except OSError as e:
                log.info("could not put back %s in %s: %s", entry.get("appid"), f, e)
                failed.append(entry)
                failed_paths.append(str(f))

    if _restart_steam(steam.steam_path(), edit):
        if failed:
            import json
            kept =[e for e in record if any(e is x for x in failed)]
            if kept:
                LAUNCH_RECORD.write_text(json.dumps(kept, indent=1), encoding="utf-8")
            else:
                LAUNCH_RECORD.unlink(missing_ok=True)
            log.info("%d launch option edits failed; uninstall stops", len(failed))
            if failed_files is not None:
                failed_files.extend(p for p in dict.fromkeys(failed_paths))
            return False
        LAUNCH_RECORD.unlink(missing_ok=True)
        return True
    log.info("Steam did not close; launch options not put back")
    return False


# install_mod's exit code when the game is not installed: setup's Finish page
# then says so instead of "installed and added to the game".
NO_GAME = 2


def install_mod(from_setup=False):
    """from_setup: run by setup, whose Finish page says it is ready, so no
    box of its own on success (Casey, 2026-10-11: one box, not OK and
    Finish). Nothing names the demo, so the wording fits the demo and the
    full game alike."""
    games = steam.find_games(steam.steam_path())
    if not games:
        if message(
                f"{GAME} is not installed in Steam, and Voyager Access needs it.\n\n"
                "Open the game's page in Steam now?\n\n"
                "After the game is installed, open the Start menu and choose "
                "\"Add Voyager Access to the game\", or run this installer again.",
                MB_YESNO | MB_ICONQUESTION) == IDYES:
            steam.open_store_page(steam.FULL)
        return NO_GAME
    while True:
        try:
            for game in games:
                install_into(game)
            break
        except modfiles.GameRunning:
            if message(f"{GAME} is running. Close the game, then choose Retry.",
                       MB_RETRYCANCEL | MB_ICONWARNING) != IDRETRY:
                return 1
        except OSError as e:
            message(f"Voyager Access could not be added to the game.\n\n{e}", MB_OK | MB_ICONWARNING)
            return 1
    set_launch_options(games)
    # From the Start menu, start the game rather than say to (Casey,
    # 2026-10-14); setup's Finish page has its own Start checkbox.
    if not from_setup:
        start_game()
    return 0


def start_game():
    """Setup's Finish starts the game (Casey, 2026-10-11): through Steam, so
    its launch options start this helper too. The full game if installed,
    else the demo."""
    import os
    games = steam.find_games(steam.steam_path())
    if not games:
        return 1
    os.startfile(f"steam://rungameid/{games[0].appid}")
    return 0


# uninstall_mod's exit code for a failure the player cannot clear by closing
# the game or Steam (a file that will not go, anything unexpected): setup
# then offers to uninstall anyway, where exit 1 (the game left running, or
# Steam would not close) stops it (pre-merge review, 2026-11-10: the same
# failure on every try left no way to uninstall at all).
UNINSTALL_ERROR = 3

# uninstall_mod's exit code when Steam's settings file could not be changed
# (for example set to read-only on purpose): the wrapper is still there, so
# the uninstall stops, but closing the game would not help. The helper has
# already named the file, so setup stops without its "close the game" box
# (Fable release review, 2026-11-11, medium 2).
LAUNCH_FILE_ERROR = 4


def uninstall_mod():
    """0 when the mod and the launch options are gone. Anything else makes
    the uninstaller stop before it deletes this exe and the data folder
    (Fable review, 2026-11-10): Steam would otherwise keep starting a
    deleted program, with the record needed to undo it deleted too."""
    try:
        return _uninstall_mod()
    except Exception:
        log.exception("--uninstall-mod failed")
        return UNINSTALL_ERROR


def _uninstall_mod():
    # The launch options go back first, and the files only once they have:
    # a stop at the Steam question (exit 1) then leaves the mod whole, as
    # setup's "nothing was uninstalled" says (Codex release review,
    # 2026-11-11: the files used to go first). A running game is asked about
    # before either, as it was before the Steam question.
    while modfiles.game_is_running():
        if message(f"{GAME} is running. Close the game, then choose Retry.",
                   MB_RETRYCANCEL | MB_ICONWARNING) != IDRETRY:
            return 1
    failed_files = []
    if not unset_launch_options(failed_files):
        if failed_files:
            message("Voyager Access could not change this Steam settings file:\n\n"
                    + "\n".join(failed_files)
                    + "\n\nSteam would still start Voyager Access from it, so nothing was "
                    "uninstalled. If the file is set to read-only, clear Read-only in its "
                    "Properties, then uninstall Voyager Access again.", MB_OK | MB_ICONWARNING)
            return LAUNCH_FILE_ERROR
        return 1
    while True:
        try:
            modfiles.uninstall_all(DATA_DIR)
            return 0
        except modfiles.GameRunning:
            if message(f"{GAME} is running. Close the game, then choose Retry.",
                       MB_RETRYCANCEL | MB_ICONWARNING) != IDRETRY:
                return 1
        except OSError as e:
            # The launch options are already back, so a game that will not
            # start from Steam is not the risk here; setup asks whether to
            # uninstall anyway.
            log.info("removing the mod's files failed: %s", e)
            return UNINSTALL_ERROR


def single_instance():
    """True for the first helper; a second one (the game started again while
    one was still running) just starts the game."""
    ctypes.windll.kernel32.CreateMutexW(None, False, "Local\\VoyagerAccessHelper")
    return ctypes.windll.kernel32.GetLastError() != 183  # ERROR_ALREADY_EXISTS


def post_install():
    """What setup runs after installing or updating. Upgrades arrive
    silently (no --install-mod), so this also sets the launch options:
    without them, nothing starts the helper and the game has no speech."""
    log.info("Voyager Access %s installed", __version__)
    relaunch = updater.relaunch_target(UPDATE_MARKER)
    keep_installed()
    games = steam.find_games(steam.steam_path())
    if games and helper_exe():
        set_launch_options(games, dx11=False)
    if relaunch:
        updater.clear_relaunch(UPDATE_MARKER)
        log.info("starting the game again (%s)", relaunch)
        import os
        os.startfile(f"steam://rungameid/{relaunch}")
    return 0


GAME_START_SECONDS = 180


def launch_game(command):
    """Steam's launch: start the game, speak while it runs, exit with it."""
    import subprocess
    if not command:
        return 1
    first = single_instance()
    # Steam runs this in place of the game, so nothing before the Popen may
    # stop the game from starting: a game without a mod update is better
    # than no game (Fable review, 2026-11-10).
    try:
        if first:
            keep_installed()
    except Exception:
        log.exception("checking the mod's files failed; starting the game anyway")
    log.info("starting the game: %s", " ".join(command))
    try:
        prepare_session_files(DEFAULT_FILE)
    except Exception:
        log.exception("preparing the session files failed; starting the game anyway")
    try:
        subprocess.Popen(command)
    except OSError as e:
        log.info("the game would not start: %s", e)
        return 1
    if not first:
        return 0
    started = time.monotonic()
    while not modfiles.game_is_running():
        if time.monotonic() - started > GAME_START_SECONDS:
            log.info("the game did not start")
            return 0
        time.sleep(1)
    log.info("game started")
    # An update's setup still running now (started when the last session
    # closed) sees this game and refuses, writing update-deferred.txt: the
    # marker is read only once it has ended, or that refusal is counted as
    # a failed update (pre-merge review, 2026-11-10).
    wait_for_setup()
    news = update_news()
    clear_game_state()
    return play_session(news=news.text, waited=news.waited)


SETUP_WAIT_SECONDS = 60


def wait_for_setup():
    """Waits, at most SETUP_WAIT_SECONDS, while an update's setup runs."""
    started = time.monotonic()
    try:
        while any(p.lower() == updater.ASSET.lower() for p in _process_names()):
            if time.monotonic() - started > SETUP_WAIT_SECONDS:
                log.info("the update's setup is still running; reading its result now")
                return
            time.sleep(1)
    except Exception:
        log.exception("could not check for a running setup")


def attach_game():
    """--attach: the mod started this helper because none was running (no
    Steam launch option, or it was reset), so join the game that is already
    running and speak until it closes (Casey, 2026-10-29: "the mod should
    start the helper whenever possible"). The game's state files are left
    alone: the mod is mid-session."""
    if not single_instance():
        log.info("attach: a helper is already running")
        return 0
    if not modfiles.game_is_running():
        log.info("attach: the game is not running")
        return 0
    log.info("attach: started by the mod; the Steam launch option is probably missing")
    keep_installed()
    return play_session(greeting="Voyager Access speech started.")


def play_session(news=None, greeting=None, waited=False):
    """Speaks and hands the mod its keys while the game runs; updates
    install when it closes. waited is update_news()'s flag: news promised
    the update installs when the game closes, so no main-menu restart."""
    session = PlaySession(waited=waited)
    tolk = open_speech(DEFAULT_TOLK)
    heartbeat = HeartbeatWatch()
    try:
        if greeting:
            tolk.say(greeting, True)
        if news:
            tolk.say(news, False)

        def keep_going():
            if not modfiles.game_is_running():
                return False
            heartbeat.check(lambda text: tolk.say(text, True))
            session.step(lambda text: tolk.say(text, True), apply_in_game)
            return not session.restart

        def on_keys(names):
            session.key(names)
            if REPORT_KEY in names:
                tolk.say("Report copied to the clipboard." if copy_report()
                         else "The report could not be copied.", True)

        while True:
            serve(tolk, DEFAULT_FILE, keep_going, on_keys=on_keys)
            if not session.restart:
                break
            if restart_for_update(tolk, session.found, session.early):
                return 0      # setup stops this copy, and the new one starts the game
            # The game would not close: keep speaking until it does, and
            # install then (Fable review, 2026-11-10: the helper used to exit
            # here and leave the running game silent).
            session.restart = False
            tolk.say("The game did not close. The Voyager Access update installs when you "
                     "close the game.", True)
    finally:
        tolk.unload()
    log.info("game exited; longest heartbeat gap %.1f s%s", heartbeat.longest,
             "" if heartbeat.armed else " (no heartbeat seen)")
    RELOAD_FLAG.unlink(missing_ok=True)
    session.wait()
    if session.found:
        install_update(session.found[0], session.found[1])
    return 0


# Updates (Casey, 2026-10-11): checked when the game starts and every ten
# minutes while it runs. Nothing checks while the game is closed: the helper
# only runs with the game.
# 1. Found soon after the game starts: the game restarts to install it, but
#    only once the mod reports the main menu (Casey, 2026-10-14: a player
#    who had already loaded a save could have been closed mid-game). If the
#    main menu is not seen within the window, it is offered as in 2.
# 2. Found later: the new Lua scripts go into the running game and the mod
#    reloads them; the rest installs when the game closes, or at once if
#    Casey presses F12. The game only saves at story points, so a game in
#    progress is never closed without that key.
# VOYAGER_UPDATE_FEED points the check elsewhere for testing (file:// works);
# VOYAGER_PLAY_CHECK_SECONDS shortens the in-game interval for testing.
PLAY_CHECK_SECONDS = int(os.environ.get("VOYAGER_PLAY_CHECK_SECONDS", 10 * 60))
# Long enough for the game to load to its main menu (about half a minute).
RESTART_WINDOW_SECONDS = 180
# The mod writes "menu" when the game makes its main menu and "game" when it
# makes the HUD or a loading screen (help.lua). It used to rewrite the file
# about once a second from a loop, and the helper took an old file as "not
# at the menu"; the mod's loops held the game long enough to swallow keys
# (firefly82, 2026-10-21), so the file is written on change only and is
# cleared when the game starts (clear_game_state), so an old "menu" from an
# earlier run never counts.
GAME_STATE = DATA_DIR / "game-state.txt"
# The mod's list of windows already read (popups.lua), kept so a reload in
# the same game does not read them again. From an earlier run of the game it
# made new windows with the same path count as read, and the personal log
# after a load was silent (VM, 2026-10-21), so it goes when the game starts.
WINDOWS_READ = DATA_DIR / "windows-read.txt"


def clear_game_state():
    for f in (GAME_STATE, WINDOWS_READ):
        try:
            f.unlink(missing_ok=True)
        except OSError:
            pass


def prepare_session_files(speech_file):
    """Before the game is started: the speech file empty, and the files
    from the last run gone (clear_game_state). The read list was deleted
    only once the game was seen running, and the mod could load it first
    (GPT review, 2026-10-21)."""
    # Start the speech file empty, before the mod can write to it: when the
    # last session left a short file, the reader started past the mod's
    # first line and "Voyager Access loaded" was missed (2026-10-11).
    try:
        Path(speech_file).parent.mkdir(parents=True, exist_ok=True)
        Path(speech_file).write_text("", encoding="utf-8")
    except OSError:
        pass
    clear_game_state()


def at_main_menu():
    """True when the mod has reported the game's main menu this run."""
    try:
        return GAME_STATE.read_text(encoding="utf-8").strip() == "menu"
    except OSError:
        return False
RESTART_KEY = "f12"
ANNOUNCE_DELAY_SECONDS = 3
UPDATE_MARKER = DATA_DIR / "pending-update.json"
# The version whose setup did not finish, and how many times (Fable review,
# 2026-11-10): without it a setup that fails on a player's computer closed
# the game at the main menu on every launch (the restart loop a tester hit
# in 0.2.3). That version is then offered on F12 and at game close only.
FAILED_UPDATE = DATA_DIR / "failed-update.json"
# Left by a silent setup that would not run because the game was running
# (VoyagerAccess.iss PrepareToInstall; Casey, 2026-11-10). That is not a
# failed update and is not counted.
UPDATE_DEFERRED = DATA_DIR / "update-deferred.txt"
UPDATE_WAITED_NEWS = ("A Voyager Access update waited because the game was running. "
                      "It installs when you close the game.")


class UpdateNews(NamedTuple):
    text: Optional[str]
    waited: bool
SETUP_LOG = DATA_DIR / "setup.log"   # the last update's installer log, for the report
RELOAD_FLAG = DATA_DIR / "reload"


class PlaySession:
    """Update checks for one run of the game. step() runs on the main thread
    about once a second; the check itself runs in a background thread."""

    def __init__(self, found=None, clock=time.monotonic, threads=True, at_menu=at_main_menu,
                 waited=False):
        self.clock = clock
        # This session said UPDATE_WAITED_NEWS ("It installs when you close
        # the game"), so it keeps its word: no restart at the main menu, only
        # F12 or closing the game (coordinator decision, 2026-11-11).
        self.waited = waited
        self.at_menu = at_menu
        self.started = clock()
        self.threads = threads
        self.found = found          # already offered in an earlier run: just offer F12
        self.offered = found is not None
        self.early = False
        self.restart = False
        self.checking = False
        self.last_check = None
        self.thread = None
        self.announce = None       # (when, text)
        self.asked = False         # F12 asked for a check; say how it came out
        self.failed = False

    def _run(self):
        try:
            found = fetch_update()
            self.failed = False
        except Exception as e:      # a failed check must never stop the speech
            log.info("update check failed: %s", e)
            found = None
            self.failed = True
        if found:
            self.early = (not self.waited
                          and self.clock() - self.started <= RESTART_WINDOW_SECONDS
                          and found[0] != failed_update()[0])
            self.found = found
        self.checking = False

    def step(self, say, apply_scripts):
        if self.asked and self.last_check is None:
            say("Checking for Voyager Access updates.")
        if self.found is None and not self.checking and (
                self.last_check is None or self.clock() - self.last_check >= PLAY_CHECK_SECONDS):
            self.checking = True
            self.last_check = self.clock()
            if self.threads:
                import threading
                self.thread = threading.Thread(target=self._run, daemon=True)
                self.thread.start()
            else:
                self._run()
        if self.asked and not self.checking and not self.found:
            self.asked = False
            say("Could not check for Voyager Access updates." if self.failed
                else f"Voyager Access is up to date, version {__version__}.")
        if self.found and not self.offered:
            if self.early:
                if self.at_menu():
                    self.asked = False
                    self.offered = True
                    self.restart = True
                    return
                if self.clock() - self.started <= RESTART_WINDOW_SECONDS:
                    return          # not at the main menu yet: wait for it
            self.asked = False
            self.offered = True
            version = self.found[0]
            if apply_scripts(self.found):
                # After the mod's own "Voyager Access loaded" from the reload.
                self.announce = (self.clock() + ANNOUNCE_DELAY_SECONDS,
                    f"Voyager Access fixes applied. Press F12 to restart the game and finish "
                    f"the update to version {version}, or it finishes when you close the game.")
            else:
                say(f"Voyager Access update {version} is ready. Press F12 to restart the game "
                    "and install it, or it installs when you close the game.")
        if self.announce and self.clock() >= self.announce[0]:
            say(self.announce[1])
            self.announce = None

    def key(self, names):
        """F12 restarts for an update already offered; otherwise it checks
        for one now (Casey, 2026-10-11). A check never closes the game: a
        found update is offered first, and a second F12 restarts."""
        if RESTART_KEY not in names:
            return
        if self.found and self.offered:
            self.restart = True
        elif not self.checking and not self.found:
            self.asked = True
            self.last_check = None

    def wait(self):
        if self.thread:
            self.thread.join(120)


def apply_in_game(found):
    """What an update found during play does to the running game: nothing.
    Reloading the mod through RELOAD_FLAG froze the game twice in four
    tries on 2026-10-11, so the update waits for
    F12 or the game closing. patch_running_game is kept for when the
    freeze is understood."""
    return False


def patch_running_game(found):
    """Puts the release's scripts into every installed copy and asks the mod
    to reload them. False when the release has none or nothing was patched."""
    scripts = found[2]
    if not scripts:
        return False
    patched = False
    for game in steam.find_games(steam.steam_path()):
        try:
            patched = modfiles.patch_scripts(game.bin_dir, scripts, DATA_DIR, game.appid) or patched
        except OSError as e:
            log.info("patching scripts in %s failed: %s", game.bin_dir, e)
    if patched:
        # A line in keys.txt, which the mod reads anyway (reload.lua): the
        # flag file it used to look for every second was one of the loops
        # that held the game long enough to swallow keys (firefly82,
        # 2026-10-21).
        from voyager.helper import DEFAULT_KEYS
        with open(DEFAULT_KEYS, "a", encoding="utf-8") as f:
            f.write("cmd:reload\n")
        log.info("scripts from %s patched into the running game", found[0])
    return patched


def restart_for_update(tolk, found, early):
    """Closes the game, installs the update and has the new helper start the
    game again. False when the game would not close (it then installs once
    the game is closed)."""
    version, path = found[0], found[1]
    log.info("update %s: restarting the game (%s)", version, "at start" if early else "F12")
    if early:
        tolk.say(f"Voyager Access update {version} found. Restarting the game to install it.", True)
    else:
        tolk.say("Restarting the game to finish the Voyager Access update.", True)
    time.sleep(5)
    exe = modfiles.close_game()
    if not exe and not modfiles.game_is_running():
        # The player closed it during the notice: close_game finds no game
        # and returns None, as for one that stayed open, and "The game did
        # not close" was said to a closed game (pre-merge review,
        # 2026-11-10). Install now; the player closed it, so it is not
        # started again.
        log.info("the game was already closed; installing")
        install_update(version, path)
        return True
    if not exe:
        log.info("the game did not close; installing after it closes")
        return False
    appid = next((g.appid for g in steam.find_games(steam.steam_path())
                  if Path(g.bin_dir) == Path(exe).parent), None)
    install_update(version, path, relaunch=appid)
    return True


def update_news():
    """What to say when the game next starts, after an update, as
    UpdateNews(text, waited). waited is True only for the line that promises
    the update installs when the game closes; play_session keeps that
    promise from the flag, never from the words (Fable release review,
    2026-11-11: a text comparison would break silently if the line were
    joined or translated)."""
    import json
    try:
        expected = json.loads(UPDATE_MARKER.read_text(encoding="utf-8")).get("expected")
    except (OSError, ValueError, AttributeError):
        expected = None
    result = updater.read_marker(UPDATE_MARKER, __version__)
    deferred = UPDATE_DEFERRED.exists()
    UPDATE_DEFERRED.unlink(missing_ok=True)
    if result == "failed" and deferred:
        log.info("update to %s waited: setup found the game running", expected)
        return UpdateNews(UPDATE_WAITED_NEWS, True)
    if result == "updated":
        log.info("updated to %s", __version__)
        FAILED_UPDATE.unlink(missing_ok=True)
        return UpdateNews(f"Voyager Access was updated to version {__version__}. "
                          "Ctrl+F12 lists what is new.", False)
    if result == "failed":
        version, count = failed_update()
        count = count + 1 if version == expected else 1
        log.info("update to %s did not finish (%d times); still %s", expected, count, __version__)
        try:
            FAILED_UPDATE.parent.mkdir(parents=True, exist_ok=True)
            FAILED_UPDATE.write_text(json.dumps({"version": expected, "count": count}),
                                     encoding="utf-8")
        except OSError as e:
            log.info("could not record the failed update: %s", e)
        if count >= 2:
            return UpdateNews("A Voyager Access update did not finish again. To install it, "
                              "download the Voyager Access installer from its GitHub releases "
                              "page and run it.", False)
        return UpdateNews("A Voyager Access update did not finish. It will try again when you "
                          "close the game, or press F12.", False)
    return UpdateNews(None, False)


def failed_update():
    """(version, times) of the update whose setup did not finish, or (None, 0)."""
    import json
    try:
        data = json.loads(FAILED_UPDATE.read_text(encoding="utf-8"))
        return data.get("version"), int(data.get("count", 1))
    except (OSError, ValueError, AttributeError, TypeError):
        return None, 0


def fetch_update():
    """Checks for and downloads a newer version: (version, installer,
    scripts folder or None) or None."""
    import os
    import tempfile
    feed = os.environ.get("VOYAGER_UPDATE_FEED", updater.FEED)
    release = updater.check(feed, __version__)
    if not release:
        return None
    log.info("update %s available", release.version)
    folder = Path(tempfile.gettempdir()) / "VoyagerAccessUpdater"
    try:
        path = updater.download(release, folder)
    except updater.UpdateError as e:
        log.info("update not installed: %s", e)
        return None
    try:
        scripts = updater.download_scripts(release, folder / "mod")
    except updater.UpdateError as e:
        log.info("scripts not patched: %s", e)
        scripts = None
    return release.version, path, scripts


def install_update(version, path, relaunch=None):
    if modfiles.game_is_running():
        return
    updater.write_marker(UPDATE_MARKER, version, relaunch=relaunch)
    log.info("running the %s installer", version)
    updater.run_installer(path, log=SETUP_LOG)


REPORT_KEY = "grave"


def build_report(helper_log, game_logs, configs):
    """What Casey needs to look into a problem on someone's computer: the
    version, the game's launch options, the helper's log, and the mod's
    lines from each game log (2026-10-11, backtick in the game)."""
    from . import launchopts
    import time as _time
    out = ["Voyager Access report, " + _time.strftime("%Y-%m-%d %H:%M"), "Version: " + __version__,
           "", "== Launch options =="]
    for cfg in configs:
        try:
            for line in launchopts.read_file(cfg).splitlines():
                if "LaunchOptions" in line and ("VoyagerAccess" in line or "dx11" in line):
                    out.append(launchopts.unescape(line.strip()))
        except OSError:
            continue
    out += ["", "== Helper log =="]
    try:
        out += Path(helper_log).read_text(encoding="utf-8", errors="replace").splitlines()[-40:]
    except OSError:
        out.append("(none)")
    # What the mod last said: beside the helper's log it shows whether speech
    # stopped at the mod or at the helper (2026-10-29).
    speech_file = Path(helper_log).with_name("speech.txt")
    if speech_file.exists():
        out += ["", "== Last speech =="]
        try:
            out += speech_file.read_text(encoding="utf-8", errors="replace").splitlines()[-30:]
        except OSError:
            out.append("(unreadable)")
    setup_log = Path(helper_log).with_name("setup.log")
    if setup_log.exists():
        out += ["", "== Last update's setup log (end) =="]
        try:
            out += setup_log.read_text(encoding="utf-8", errors="replace").splitlines()[-25:]
        except OSError:
            out.append("(unreadable)")
    for game_log in game_logs:
        out += ["", "== Game log: %s ==" % game_log]
        try:
            lines = Path(game_log).read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            out.append("(none)")
            continue
        out += [l for l in lines if "[VoyagerAccess]" in l or "error" in l.lower()][-120:]
    return "\r\n".join(out)


def copy_to_clipboard(text):
    """Puts text on the Windows clipboard (Unicode)."""
    k32, u32 = ctypes.windll.kernel32, ctypes.windll.user32
    k32.GlobalAlloc.restype = ctypes.c_void_p
    k32.GlobalLock.restype = ctypes.c_void_p
    k32.GlobalLock.argtypes = [ctypes.c_void_p]
    k32.GlobalUnlock.argtypes = [ctypes.c_void_p]
    u32.SetClipboardData.argtypes = [ctypes.c_uint, ctypes.c_void_p]
    data = (text + "\0").encode("utf-16-le")
    for _ in range(10):
        if u32.OpenClipboard(None):
            break
        time.sleep(0.1)
    else:
        return False
    try:
        u32.EmptyClipboard()
        h = k32.GlobalAlloc(0x0002, len(data))   # GMEM_MOVEABLE
        p = k32.GlobalLock(h)
        ctypes.memmove(p, data, len(data))
        k32.GlobalUnlock(h)
        return bool(u32.SetClipboardData(13, h))  # CF_UNICODETEXT
    finally:
        u32.CloseClipboard()


def copy_report():
    from . import launchopts
    games = steam.find_games(steam.steam_path())
    text = build_report(DATA_DIR / "helper.log",
                        [Path(g.bin_dir) / "ue4ss" / "UE4SS.log" for g in games],
                        launchopts.config_files(steam.steam_path()))
    ok = copy_to_clipboard(text)
    log.info("report copied to the clipboard" if ok else "report could not be copied")
    return ok


def speech_check(report):
    """Checks the bundled files a silent build would be missing."""
    lines, ok = [f"Voyager Access {__version__}"], True
    for rel in ("tolk/Tolk.dll", "tolk/nvdaControllerClient64.dll", "payload/dwmapi.dll",
                "payload/ue4ss/UE4SS.dll", "payload/ue4ss/Mods/VoyagerAccess/Scripts/main.lua",
                "payload/ue4ss/Mods/VoyagerAccess/enabled.txt"):
        present = (RESOURCES / rel).is_file()
        ok = ok and present
        lines.append(f"{'present' if present else 'MISSING'} {rel}")
    try:
        tolk = Tolk(DEFAULT_TOLK)
        lines.append(f"Tolk loaded; screen reader: {tolk.name()}")
        tolk.unload()
    except OSError as e:
        ok = False
        lines.append(f"Tolk failed to load: {e}")
    lines.append("OK" if ok else "FAILED")
    Path(report).write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0 if ok else 1


def main(argv=None):
    ap = argparse.ArgumentParser(prog="VoyagerAccess")
    group = ap.add_mutually_exclusive_group()
    group.add_argument("--install-mod", action="store_true")
    group.add_argument("--uninstall-mod", action="store_true")
    group.add_argument("--start-game", action="store_true")
    group.add_argument("--speech-check", metavar="REPORT")
    group.add_argument("--launch", nargs=argparse.REMAINDER, metavar="GAME")
    group.add_argument("--attach", action="store_true")   # started by the mod (helperstart.lua)
    ap.add_argument("--from-setup", action="store_true")
    args = ap.parse_args(argv)
    setup_logging()
    if args.attach:
        return attach_game()
    if args.install_mod:
        return install_mod(from_setup=args.from_setup)
    if args.uninstall_mod:
        return uninstall_mod()
    if args.start_game:
        return start_game()
    if args.speech_check:
        return speech_check(args.speech_check)
    if args.launch is not None:
        return launch_game(args.launch)
    return post_install()


if __name__ == "__main__":
    sys.exit(main())
