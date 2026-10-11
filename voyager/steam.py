"""Finds Star Trek: Voyager - Across the Unknown through Steam's own files.

Steam lists its library folders in steamapps\\libraryfolders.vdf, and each
installed game has steamapps\\appmanifest_<appid>.acf naming its folder under
steamapps\\common. Both are Valve's KeyValues text format.
"""
import re
import webbrowser
import os
from dataclasses import dataclass
from pathlib import Path

FULL = "2643390"
DEMO = "4054540"
GAME_EXE = "STVoyager-Win64-Shipping.exe"
BIN_SUBDIR = Path("STVoyager") / "Binaries" / "Win64"

_TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|([{}])')


def parse_vdf(text):
    """Parses KeyValues text into nested dicts. Keys are lower-cased."""
    stack = [{}]
    key = None
    for m in _TOKEN.finditer(text):
        quoted, brace = m.groups()
        if brace == "{":
            child = {}
            stack[-1][key] = child
            stack.append(child)
            key = None
        elif brace == "}":
            if len(stack) > 1:
                stack.pop()
        elif key is None:
            key = quoted.lower()
        else:
            stack[-1][key] = re.sub(r"\\(.)", r"\1", quoted)
            key = None
    return stack[0]


@dataclass
class Game:
    appid: str
    name: str
    bin_dir: Path       # ...\STVoyager\Binaries\Win64, where UE4SS goes


def steam_path():
    """Steam's install folder from the registry, or None."""
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam") as k:
            return Path(winreg.QueryValueEx(k, "SteamPath")[0])
    except OSError:
        return None


def _libraries(steam):
    try:
        data = parse_vdf((steam / "steamapps" / "libraryfolders.vdf").read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return [steam]
    libs = [Path(v["path"]) for v in data.get("libraryfolders", {}).values()
            if isinstance(v, dict) and "path" in v]
    return libs or [steam]


def find_games(steam=None):
    """Installed copies of the game, full game first."""
    if steam is None:
        return []
    games = []
    for appid in (FULL, DEMO):
        for lib in _libraries(Path(steam)):
            try:
                text = (lib / "steamapps" / f"appmanifest_{appid}.acf").read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            state = parse_vdf(text).get("appstate", {})
            folder = state.get("installdir")
            if not folder:
                continue
            bin_dir = lib / "steamapps" / "common" / folder / BIN_SUBDIR
            if (bin_dir / GAME_EXE).is_file():
                games.append(Game(appid, state.get("name", folder), bin_dir))
                break
    return games


def open_install_dialog(appid=DEMO):
    """Asks Steam to show its install dialog for the game."""
    os.startfile(f"steam://install/{appid}")


def open_store_page(appid=FULL):
    webbrowser.open(f"https://store.steampowered.com/app/{appid}/")
