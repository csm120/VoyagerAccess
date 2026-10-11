"""Puts the mod's files into the game folder and takes them out again.

The payload folder mirrors the game's Binaries\\Win64 folder: dwmapi.dll
(UE4SS's loader), ue4ss\\ (UE4SS itself) and ue4ss\\Mods\\VoyagerAccess.
Every file added is listed in a manifest in the data folder, and any file
that was already there (another mod's UE4SS, say) is backed up first, so
uninstall leaves the game folder exactly as it was found.
"""
import json
import shutil
from pathlib import Path

from .steam import GAME_EXE


class GameRunning(Exception):
    pass


def game_is_running():
    return _game_pid() is not None


def close_game(timeout=90):
    """Asks the running game to close, as its window's Close does, and waits.
    Returns the game's exe path once it has exited, or None (not running, or
    still running after timeout). Never kills it. The request is repeated
    every two seconds: one sent five seconds after launch, while the game
    was still loading, was ignored (2026-10-11)."""
    import ctypes
    import ctypes.wintypes as wt
    import time
    pid = _game_pid()
    if pid is None:
        return None
    k32, user32 = ctypes.windll.kernel32, ctypes.windll.user32
    exe = None
    k32.OpenProcess.restype = wt.HANDLE
    handle = k32.OpenProcess(0x1000, False, pid)   # PROCESS_QUERY_LIMITED_INFORMATION
    if handle:
        buf = ctypes.create_unicode_buffer(1024)
        size = wt.DWORD(len(buf))
        if k32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
            exe = buf.value
        k32.CloseHandle(handle)

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def each(hwnd, _):
        owner = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            user32.PostMessageW(hwnd, 0x0010, 0, 0)   # WM_CLOSE
        return True

    deadline = time.monotonic() + timeout
    next_ask = 0.0
    while time.monotonic() < deadline:
        if not game_is_running():
            return exe
        if time.monotonic() >= next_ask:
            user32.EnumWindows(each, 0)
            next_ask = time.monotonic() + 2
        time.sleep(0.5)
    return None


def _game_pid():
    import ctypes
    import ctypes.wintypes as wt
    # Toolhelp process snapshot; avoids starting tasklist.
    TH32CS_SNAPPROCESS = 0x2

    class PROCESSENTRY32W(ctypes.Structure):
        _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ProcessID", wt.DWORD),
                    ("th32DefaultHeapID", ctypes.c_size_t), ("th32ModuleID", wt.DWORD),
                    ("cntThreads", wt.DWORD), ("th32ParentProcessID", wt.DWORD),
                    ("pcPriClassBase", ctypes.c_long), ("dwFlags", wt.DWORD),
                    ("szExeFile", ctypes.c_wchar * 260)]

    k32 = ctypes.windll.kernel32
    k32.CreateToolhelp32Snapshot.restype = wt.HANDLE
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    entry = PROCESSENTRY32W()
    entry.dwSize = ctypes.sizeof(entry)
    try:
        ok = k32.Process32FirstW(snap, ctypes.byref(entry))
        while ok:
            if entry.szExeFile.lower() == GAME_EXE.lower():
                return entry.th32ProcessID
            ok = k32.Process32NextW(snap, ctypes.byref(entry))
        return None
    finally:
        k32.CloseHandle(snap)


def _manifest_path(data_dir, appid):
    return Path(data_dir) / "installs" / f"{appid}.json"


def load_manifest(data_dir, appid):
    try:
        return json.loads(_manifest_path(data_dir, appid).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def is_installed(data_dir, appid):
    return load_manifest(data_dir, appid) is not None


def install(bin_dir, payload_dir, data_dir, appid, game_running=None, version=None):
    """Copies the payload into bin_dir. Re-running it updates in place."""
    if (game_running or game_is_running)():
        raise GameRunning()
    bin_dir, payload_dir = Path(bin_dir), Path(payload_dir)
    backup_dir = Path(data_dir) / "backup" / appid
    old = load_manifest(data_dir, appid) or {"files": [], "backed_up": [], "created": []}
    ours = set(old["files"])
    backed_up = set(old["backed_up"])
    new_files = sorted(p.relative_to(payload_dir).as_posix() for p in payload_dir.rglob("*") if p.is_file())
    # Top-level folders this install creates; uninstall also clears what
    # UE4SS wrote into them (UE4SS.log).
    created = set(old.get("created", [])) | {
        p.name for p in payload_dir.iterdir() if p.is_dir() and not (bin_dir / p.name).exists()}
    for rel in new_files:
        target = bin_dir / rel
        if target.exists() and rel not in ours and rel not in backed_up:
            dest = backup_dir / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, dest)
            backed_up.add(rel)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(payload_dir / rel, target)
    # Files an earlier version installed that this one no longer ships.
    for rel in ours - set(new_files):
        _remove(bin_dir, rel, backup_dir, rel in backed_up)
        backed_up.discard(rel)
    path = _manifest_path(data_dir, appid)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"version": version, "bin_dir": str(bin_dir), "files": new_files,
                                "backed_up": sorted(backed_up), "created": sorted(created)},
                               indent=1), encoding="utf-8")


SCRIPTS_REL = "ue4ss/Mods/VoyagerAccess/Scripts"


def patch_scripts(bin_dir, scripts_dir, data_dir, appid):
    """Copies new Lua scripts into an installed mod, game running or not (the
    game does not lock them; the mod reloads them on request). New files go
    into the manifest so uninstall removes them; the version stays, so the
    full install still runs once the game closes."""
    manifest = load_manifest(data_dir, appid)
    if manifest is None:
        return False
    target = Path(bin_dir) / SCRIPTS_REL
    files = set(manifest["files"])
    for src in sorted(Path(scripts_dir).glob("*.lua")):
        shutil.copy2(src, target / src.name)
        files.add(f"{SCRIPTS_REL}/{src.name}")
    manifest["files"] = sorted(files)
    _manifest_path(data_dir, appid).write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    return True


def _remove(bin_dir, rel, backup_dir, restore):
    target = bin_dir / rel
    if restore and (backup_dir / rel).is_file():
        shutil.copy2(backup_dir / rel, target)
        return
    target.unlink(missing_ok=True)
    # Remove folders this left empty, never bin_dir itself.
    parent = target.parent
    while parent != bin_dir and bin_dir in parent.parents:
        try:
            parent.rmdir()
        except OSError:
            break
        parent = parent.parent


def uninstall(bin_dir, data_dir, appid, game_running=None):
    """Removes what install added and puts back what it replaced."""
    manifest = load_manifest(data_dir, appid)
    if manifest is None:
        return
    if (game_running or game_is_running)():
        raise GameRunning()
    bin_dir = Path(bin_dir)
    backup_dir = Path(data_dir) / "backup" / appid
    backed_up = set(manifest["backed_up"])
    for rel in sorted(manifest["files"], key=lambda r: -r.count("/")):
        _remove(bin_dir, rel, backup_dir, rel in backed_up)
    for name in manifest.get("created", []):
        _clear_generated(bin_dir / name)
    shutil.rmtree(backup_dir, ignore_errors=True)
    _manifest_path(data_dir, appid).unlink()


GENERATED = ("*.log", "*.dmp")


def _clear_generated(folder):
    """Deletes logs and dumps UE4SS left in a folder install created, then
    any folders left empty. Other mods' files stay."""
    if not folder.is_dir():
        return
    for pattern in GENERATED:
        for p in folder.rglob(pattern):
            p.unlink(missing_ok=True)
    for d in sorted((p for p in folder.rglob("*") if p.is_dir()), key=lambda p: -len(p.parts)):
        try:
            d.rmdir()
        except OSError:
            pass
    try:
        folder.rmdir()
    except OSError:
        pass


def uninstall_all(data_dir, game_running=None):
    """Uninstalls from every game folder a manifest names."""
    for path in sorted((Path(data_dir) / "installs").glob("*.json")):
        manifest = load_manifest(data_dir, path.stem)
        if manifest:
            uninstall(manifest["bin_dir"], data_dir, path.stem, game_running)