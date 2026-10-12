"""Checks for a newer Voyager Access and installs it, while the game is closed.

The release feed is GitHub's "latest release" for the project: the newest
release that is neither a draft nor a pre-release (a pre-release is never
offered, so never publish a shipping build as one). The release must carry
VoyagerAccessSetup.exe and VoyagerAccessSetup.exe.sha256. The installer is
downloaded, checked against its checksum, and run silently: setup stops the
running helper itself and starts the new one, so no batch file is needed.

The checksum catches a broken or truncated download. It is not a security
control: whoever controls the feed controls both files.

Patterns from KeyQuest's updater (windows-app-self-updater skill).
"""
import hashlib
import json
import re
import subprocess
import urllib.request
from dataclasses import dataclass
from pathlib import Path

FEED = "https://api.github.com/repos/csm120/VoyagerAccess/releases/latest"
ASSET = "VoyagerAccessSetup.exe"
# The mod's Lua scripts alone, for patching a running game (optional).
SCRIPTS_ASSET = "VoyagerAccessMod.zip"
TIMEOUT = 30


class UpdateError(Exception):
    pass


@dataclass
class Release:
    version: str
    installer_url: str
    checksum_url: str | None
    scripts_url: str | None = None
    scripts_checksum_url: str | None = None


def _numbers(version):
    m = re.fullmatch(r"v?(\d+(?:\.\d+)*)", version.strip())
    if not m:
        return None
    return [int(n) for n in m.group(1).split(".")]


def is_newer(candidate, current):
    a, b = _numbers(candidate), _numbers(current)
    if a is None or b is None:
        return False
    width = max(len(a), len(b))
    return a + [0] * (width - len(a)) > b + [0] * (width - len(b))


def _fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "VoyagerAccess-updater",
                                               "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read()


def check(feed, current):
    """The newer release, or None (no newer one, or the feed unreachable)."""
    try:
        data = json.loads(_fetch(feed))
    except (OSError, ValueError):
        return None
    if data.get("draft") or data.get("prerelease"):
        return None
    tag = str(data.get("tag_name", ""))
    if not is_newer(tag, current):
        return None
    urls = {a.get("name"): a.get("browser_download_url") for a in data.get("assets", [])}
    if not urls.get(ASSET):
        return None
    return Release(tag.lstrip("v"), urls[ASSET], urls.get(ASSET + ".sha256"),
                   urls.get(SCRIPTS_ASSET), urls.get(SCRIPTS_ASSET + ".sha256"))


def download(release, folder):
    """Downloads and verifies the installer; returns its path."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    if not release.checksum_url:
        raise UpdateError("the release has no checksum file")
    try:
        expected = _fetch(release.checksum_url).decode("ascii", "replace").split()[0].lower()
        body = _fetch(release.installer_url)
    except (OSError, IndexError) as e:
        raise UpdateError(f"download failed: {e}") from e
    if hashlib.sha256(body).hexdigest() != expected:
        raise UpdateError("the download does not match its checksum")
    path = folder / ASSET
    path.write_bytes(body)
    return path


def download_scripts(release, folder):
    """Downloads, verifies and unpacks the release's Lua scripts; returns the
    Scripts folder, or None when the release has none."""
    import io
    import shutil
    import zipfile
    if not release.scripts_url:
        return None
    if not release.scripts_checksum_url:
        raise UpdateError("the scripts have no checksum file")
    try:
        expected = _fetch(release.scripts_checksum_url).decode("ascii", "replace").split()[0].lower()
        body = _fetch(release.scripts_url)
    except (OSError, IndexError) as e:
        raise UpdateError(f"scripts download failed: {e}") from e
    if hashlib.sha256(body).hexdigest() != expected:
        raise UpdateError("the scripts do not match their checksum")
    folder = Path(folder)
    if folder.exists():
        shutil.rmtree(folder)
    with zipfile.ZipFile(io.BytesIO(body)) as z:
        for n in z.namelist():
            # Windows PowerShell 5's Compress-Archive writes backslashes.
            name = n.replace(chr(92), "/")
            rest = name[len("Scripts/"):]
            if name.startswith("Scripts/") and name.endswith(".lua") and "/" not in rest \
                    and ".." not in rest:
                target = folder / "Scripts" / rest
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(z.read(n))
    return folder / "Scripts"


def run_installer(path):
    """Starts the installer silently, outside this process: setup stops the
    running helper (this process) and starts the new one."""
    flags = 0x08000000 | 0x00000200   # CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP
    subprocess.Popen([str(path), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART"],
                     creationflags=flags, close_fds=True)


def write_marker(marker, version, relaunch=None):
    """relaunch: the Steam app id to start again once the new helper is up."""
    data = {"expected": version}
    if relaunch:
        data["relaunch"] = relaunch
    Path(marker).parent.mkdir(parents=True, exist_ok=True)
    Path(marker).write_text(json.dumps(data), encoding="utf-8")


def relaunch_target(marker):
    """The app id to start again after the update, or None. Read it before
    read_marker, which removes the marker."""
    try:
        return json.loads(Path(marker).read_text(encoding="utf-8")).get("relaunch")
    except (OSError, ValueError, AttributeError):
        return None


def clear_relaunch(marker):
    """Drops the relaunch request once acted on, keeping "expected" so the
    next game start can still say whether the update worked."""
    try:
        data = json.loads(Path(marker).read_text(encoding="utf-8"))
        data.pop("relaunch", None)
        Path(marker).write_text(json.dumps(data), encoding="utf-8")
    except (OSError, ValueError, AttributeError):
        pass


def read_marker(marker, running):
    """After an update: "updated", "failed", or None when there was none.
    The marker is removed once read."""
    try:
        expected = json.loads(Path(marker).read_text(encoding="utf-8"))["expected"]
    except (OSError, ValueError, KeyError):
        return None
    Path(marker).unlink(missing_ok=True)
    return "updated" if not is_newer(expected, running) else "failed"
