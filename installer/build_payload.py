"""Assembles build\\payload: exactly what goes into the game's Binaries\\Win64.

    dwmapi.dll and ue4ss\\   from the vendored UE4SS release zip
    ue4ss\\Mods\\VoyagerAccess  from mod\\VoyagerAccess
"""
import shutil
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# None when vendor/ is missing (the public copy): the tests import this
# module, and only a build needs the zip.
UE4SS_ZIP = next((REPO / "vendor").glob("UE4SS_*.zip"), None)
OUT = REPO / "build" / "payload"


# UE4SS's own developer mods, on in its release mods.txt. Keybinds binds
# object and header dumps to Ctrl+J and Ctrl+H, which can freeze the game
# for a player who presses them; the console and cheat enablers are for
# development only (review of an outside guide, 2026-10-17).
DEV_MODS = ("Keybinds", "ConsoleEnablerMod", "ConsoleCommandsMod", "CheatManagerEnablerMod")


def player_mods_txt(text):
    """mods.txt with the developer mods switched off, everything else kept."""
    out = []
    for line in text.splitlines():
        name = line.split(":", 1)[0].strip()
        if ":" in line and name in DEV_MODS:
            line = f"{name} : 0"
        out.append(line)
    return "\n".join(out) + "\n"


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    if UE4SS_ZIP is None:
        raise SystemExit("No vendor/UE4SS_*.zip: put the UE4SS release zip in vendor/ first.")
    with zipfile.ZipFile(UE4SS_ZIP) as z:
        z.extractall(OUT)
    mods = OUT / "ue4ss" / "Mods" / "mods.txt"
    mods.write_text(player_mods_txt(mods.read_text(encoding="utf-8")), encoding="utf-8")
    shutil.copytree(REPO / "mod" / "VoyagerAccess", OUT / "ue4ss" / "Mods" / "VoyagerAccess")
    # What's new, read in the game with Ctrl+F12 (whatsnew.lua).
    shutil.copy2(REPO / "docs" / "WHATS_NEW.md", OUT / "ue4ss" / "Mods" / "VoyagerAccess" / "whats_new.md")
    # Starts the helper with no window (helperstart.lua; built and signed by
    # build.ps1 through build_native.ps1, 2026-10-29).
    native = REPO / "build" / "native" / "voystart.dll"
    if native.is_file():
        shutil.copy2(native, OUT / "ue4ss" / "Mods" / "VoyagerAccess" / "voystart.dll")
    for required in ("dwmapi.dll", "ue4ss/UE4SS.dll", "ue4ss/Mods/VoyagerAccess/enabled.txt",
                     "ue4ss/Mods/VoyagerAccess/Scripts/main.lua", "ue4ss/Mods/VoyagerAccess/voystart.dll"):
        if not (OUT / required).is_file():
            sys.exit(f"payload is missing {required}")
    print(f"payload: {sum(1 for p in OUT.rglob('*') if p.is_file())} files in {OUT}")


if __name__ == "__main__":
    main()
