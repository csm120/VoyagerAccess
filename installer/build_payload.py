"""Assembles build\\payload: exactly what goes into the game's Binaries\\Win64.

    dwmapi.dll and ue4ss\\   from the vendored UE4SS release zip
    ue4ss\\Mods\\VoyagerAccess  from mod\\VoyagerAccess
"""
import shutil
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UE4SS_ZIP = next((REPO / "vendor").glob("UE4SS_*.zip"))
OUT = REPO / "build" / "payload"


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    with zipfile.ZipFile(UE4SS_ZIP) as z:
        z.extractall(OUT)
    shutil.copytree(REPO / "mod" / "VoyagerAccess", OUT / "ue4ss" / "Mods" / "VoyagerAccess")
    for required in ("dwmapi.dll", "ue4ss/UE4SS.dll", "ue4ss/Mods/VoyagerAccess/enabled.txt",
                     "ue4ss/Mods/VoyagerAccess/Scripts/main.lua"):
        if not (OUT / required).is_file():
            sys.exit(f"payload is missing {required}")
    print(f"payload: {sum(1 for p in OUT.rglob('*') if p.is_file())} files in {OUT}")


if __name__ == "__main__":
    main()
