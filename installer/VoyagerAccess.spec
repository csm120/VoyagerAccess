# PyInstaller spec for VoyagerAccess.exe (one folder, no console window).
# Build with installer\build.ps1, which assembles build\payload first.
from pathlib import Path

REPO = Path(SPECPATH).parent
TOLK = REPO / "vendor" / "tolk"

# SAAPI64.dll (System Access) is left out: its redistribution terms are
# unknown (the project's license research). Tolk skips System Access without it.
datas = [
    (str(TOLK / "Tolk.dll"), "tolk"),
    (str(TOLK / "nvdaControllerClient64.dll"), "tolk"),
    (str(REPO / "build" / "payload"), "payload"),
]

a = Analysis([str(REPO / "installer" / "launch.py")], pathex=[str(REPO)], datas=datas)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name="VoyagerAccess", console=False)
coll = COLLECT(exe, a.binaries, a.datas, name="VoyagerAccess")
