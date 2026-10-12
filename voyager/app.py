"""Voyager Access: the program the installer puts on the computer.

    VoyagerAccess.exe --launch CMD...   Steam runs this in place of the game (the
                                        game's launch options): put the mod in if
                                        needed, start CMD (the game), speak and check
                                        for updates while it runs, exit with it
    VoyagerAccess.exe                   what setup runs after installing: put the
                                        mod in, set the launch options if missing,
                                        start the game again after an update, exit
    VoyagerAccess.exe --install-mod     put the mod into the game, with a message
    VoyagerAccess.exe --uninstall-mod   take it out of every game it was put in
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
import time
from pathlib import Path

from . import modfiles, steam, updater
from .helper import DATA_DIR, DEFAULT_FILE, DEFAULT_TOLK, RESOURCES, Tolk, serve
from .version import __version__

PAYLOAD = RESOURCES / "payload"
TITLE = "Voyager Access"
GAME = "Star Trek: Voyager - Across the Unknown"

log = logging.getLogger("voyager")

MB_OK, MB_YESNOCANCEL, MB_RETRYCANCEL = 0x0, 0x3, 0x5
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
    edit()
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


def set_launch_options(games, dx11=True, ask=None):
    """Sets each game's Steam launch options so Steam starts this helper,
    which starts the game (nothing runs at Windows sign-in; Casey,
    2026-10-11), and adds -dx11 (the game crashed under DirectX 12 on
    Casey's computer, 2026-10-10). Steam has to be closed while its file
    is edited. What is added is recorded, so uninstall removes only that.
    Returns False when the player declined or Steam would not close."""
    import json
    from . import launchopts
    todo = _needs_launch_edit(games, dx11)
    if not todo:
        return True
    if steam_running() and message(ask or (
            "Voyager Access starts together with the game, so nothing of it runs when you are not "
            "playing. To set that up, and to start the game in DirectX 11 mode, which some computers "
            "need, Steam has to close for a moment and start again.\n\n"
            "Close and restart Steam now? Without this, the game has no speech."),
            MB_YESNOCANCEL | MB_ICONQUESTION) != IDYES:
        log.info("launch options skipped by the player")
        return False
    record = _load_launch_record()
    exe = helper_exe()

    def edit():
        for f, appid, add_dx11, wrap in todo:
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

    if _restart_steam(steam.steam_path(), edit):
        LAUNCH_RECORD.parent.mkdir(parents=True, exist_ok=True)
        LAUNCH_RECORD.write_text(json.dumps(record, indent=1), encoding="utf-8")
        return True
    log.info("Steam did not close; launch options not set")
    return False


def unset_launch_options():
    """Removes what set_launch_options added (the wrapper and -dx11), and
    nothing else."""
    from . import launchopts
    record = _load_launch_record()
    if not record:
        return
    if steam_running() and message(
            "Voyager Access changed the game's launch options in Steam. To put them back, Steam has to "
            "close for a moment and start again.\n\nClose and restart Steam now?",
            MB_YESNOCANCEL | MB_ICONQUESTION) != IDYES:
        return

    def edit():
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
            except OSError:
                continue

    if _restart_steam(steam.steam_path(), edit):
        LAUNCH_RECORD.unlink(missing_ok=True)


def install_mod():
    games = steam.find_games(steam.steam_path())
    if not games:
        answer = message(
            f"{GAME} is not installed in Steam, and Voyager Access needs it.\n\n"
            "Yes opens Steam's install window for the free demo.\n"
            "No opens the full game's store page.\n"
            "Cancel does neither.\n\n"
            "Once the game is installed, Voyager Access adds itself to it automatically.",
            MB_YESNOCANCEL | MB_ICONQUESTION)
        if answer == IDYES:
            steam.open_install_dialog(steam.DEMO)
        elif answer == IDNO:
            steam.open_store_page(steam.FULL)
        return 0
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
    names = " and ".join(g.name for g in games)
    message(f"Voyager Access is ready for {names}.\n\n"
            "Start the game from Steam as usual. Speech starts when the game loads.")
    return 0


def uninstall_mod():
    while True:
        try:
            modfiles.uninstall_all(DATA_DIR)
            unset_launch_options()
            return 0
        except modfiles.GameRunning:
            if message(f"{GAME} is running. Close the game, then choose Retry.",
                       MB_RETRYCANCEL | MB_ICONWARNING) != IDRETRY:
                return 1


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
        set_launch_options(games, dx11=False, ask=(
            "Voyager Access now starts together with the game, so nothing of it runs when you are not "
            "playing. To set that up, Steam has to close for a moment and start again.\n\n"
            "Close and restart Steam now? Without this, the game has no speech."))
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
    if first:
        keep_installed()
    log.info("starting the game: %s", " ".join(command))
    # Start the speech file empty, before the mod can write to it: when the
    # last session left a short file, the reader started past the mod's
    # first line and "Voyager Access loaded" was missed (2026-10-11).
    try:
        Path(DEFAULT_FILE).parent.mkdir(parents=True, exist_ok=True)
        Path(DEFAULT_FILE).write_text("", encoding="utf-8")
    except OSError:
        pass
    try:
        subprocess.Popen(command)
    except OSError as e:
        log.info("the game would not start: %s", e)
        return 1
    if not first:
        return 0
    news = update_news()
    started = time.monotonic()
    while not modfiles.game_is_running():
        if time.monotonic() - started > GAME_START_SECONDS:
            log.info("the game did not start")
            return 0
        time.sleep(1)
    log.info("game started")
    session = PlaySession()
    tolk = Tolk(DEFAULT_TOLK)
    try:
        if news:
            tolk.say(news, False)

        def keep_going():
            if not modfiles.game_is_running():
                return False
            session.step(lambda text: tolk.say(text, True), apply_in_game)
            return not session.restart

        serve(tolk, DEFAULT_FILE, keep_going, on_keys=session.key)
        if session.restart and restart_for_update(tolk, session.found, session.early):
            return 0      # setup stops this copy, and the new one starts the game
    finally:
        tolk.unload()
    log.info("game exited")
    RELOAD_FLAG.unlink(missing_ok=True)
    session.wait()
    if session.found:
        install_update(session.found[0], session.found[1])
    return 0


# Updates (Casey, 2026-10-11): checked when the game starts and every ten
# minutes while it runs. Nothing checks while the game is closed: the helper
# only runs with the game.
# 1. Found within a minute of the game starting (intro or main menu): the
#    game restarts to install it.
# 2. Found later: the new Lua scripts go into the running game and the mod
#    reloads them; the rest installs when the game closes, or at once if
#    Casey presses F12. The game only saves at story points, so a game in
#    progress is never closed without that key.
# VOYAGER_UPDATE_FEED points the check elsewhere for testing (file:// works);
# VOYAGER_PLAY_CHECK_SECONDS shortens the in-game interval for testing.
PLAY_CHECK_SECONDS = int(os.environ.get("VOYAGER_PLAY_CHECK_SECONDS", 10 * 60))
RESTART_WINDOW_SECONDS = 60
RESTART_KEY = "f12"
ANNOUNCE_DELAY_SECONDS = 3
UPDATE_MARKER = DATA_DIR / "pending-update.json"
RELOAD_FLAG = DATA_DIR / "reload"


class PlaySession:
    """Update checks for one run of the game. step() runs on the main thread
    about once a second; the check itself runs in a background thread."""

    def __init__(self, found=None, clock=time.monotonic, threads=True):
        self.clock = clock
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
            self.early = self.clock() - self.started <= RESTART_WINDOW_SECONDS
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
            self.asked = False
            self.offered = True
            if self.early:
                self.restart = True
                return
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
        RELOAD_FLAG.write_text("")
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
    if not exe:
        log.info("the game did not close; installing after it closes")
        return False
    appid = next((g.appid for g in steam.find_games(steam.steam_path())
                  if Path(g.bin_dir) == Path(exe).parent), None)
    install_update(version, path, relaunch=appid)
    return True


def update_news():
    """What to say when the game next starts, after an update."""
    result = updater.read_marker(UPDATE_MARKER, __version__)
    if result == "updated":
        log.info("updated to %s", __version__)
        return f"Voyager Access was updated to version {__version__}."
    if result == "failed":
        log.info("update did not finish; still %s", __version__)
        return "A Voyager Access update did not finish. It will try again later."
    return None


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
    updater.run_installer(path)


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
    group.add_argument("--speech-check", metavar="REPORT")
    group.add_argument("--launch", nargs=argparse.REMAINDER, metavar="GAME")
    args = ap.parse_args(argv)
    setup_logging()
    if args.install_mod:
        return install_mod()
    if args.uninstall_mod:
        return uninstall_mod()
    if args.speech_check:
        return speech_check(args.speech_check)
    if args.launch is not None:
        return launch_game(args.launch)
    return post_install()


if __name__ == "__main__":
    sys.exit(main())
