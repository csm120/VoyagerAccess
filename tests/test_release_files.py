"""The release files build.ps1 leaves in dist\\installer.

Casey, 2026-11-11: while live patching is off, a release uploads only
VoyagerAccessSetup.exe and its .sha256. VoyagerAccessMod.zip makes old
helpers (0.1.2 to 0.1.9) patch a running game, which can freeze it. The
rule was written down in the project's notes, yet 0.3.91 to 0.4.2 uploaded the zip anyway,
because a stale note said "all four files" and each release copied the
last command. A written rule failed repeatedly, so the build no longer
makes the zip at all unless -LivePatching says live patching is back; the
old four-file upload from dist\\installer then fails on a missing file. It
does not stop a -LivePatching build, a zip made by hand, or an upload from
another folder.

These run the real installer\\release-files.ps1 on a temporary folder.
They prove what the step writes and removes, not what gh uploads.
"""
import hashlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STEP = ROOT / "installer" / "release-files.ps1"
BUILD = (ROOT / "installer" / "build.ps1").read_text(encoding="utf-8")
def find_pwsh():
    """PowerShell 7 from PATH or its usual install folders. Not found is a
    failure, not a skip: a skipped barrier test reads as a pass (Fable
    re-review, 2026-11-11: four skipped from Git Bash)."""
    import os
    found = shutil.which("pwsh")
    if found:
        return found
    for base in (os.environ.get("ProgramFiles", r"C:\Program Files"),
                 os.environ.get("ProgramW6432", r"C:\Program Files"),
                 os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "PowerShell")):
        for sub in ("PowerShell\\7", "7", ""):
            candidate = Path(base) / sub / "pwsh.exe"
            if candidate.is_file():
                return str(candidate)
    return None


PWSH = find_pwsh()


class ReleaseFilesTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(PWSH, "PowerShell 7 (pwsh.exe) was not found on PATH or in its install "
                              "folders; the release-files barrier is untested")
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.out = root / "dist" / "installer"
        self.out.mkdir(parents=True)
        (self.out / "VoyagerAccessSetup.exe").write_bytes(b"setup bytes")
        self.scripts = root / "scripts"
        self.scripts.mkdir()
        (self.scripts / "main.lua").write_text("-- mod", encoding="utf-8")
        self.stage = root / "stage"

    def tearDown(self):
        self.tmp.cleanup()

    def run_step(self, *extra):
        cmd = [PWSH, "-NoProfile", "-NonInteractive", "-File", str(STEP),
               "-Out", str(self.out), "-Scripts", str(self.scripts), "-Stage", str(self.stage), *extra]
        p = subprocess.run(cmd, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=120)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return sorted(f.name for f in self.out.iterdir())

    def test_by_default_only_the_setup_and_its_checksum(self):
        self.assertEqual(self.run_step(), ["VoyagerAccessSetup.exe", "VoyagerAccessSetup.exe.sha256"])
        digest = hashlib.sha256(b"setup bytes").hexdigest()
        self.assertEqual((self.out / "VoyagerAccessSetup.exe.sha256").read_text(),
                         f"{digest}  VoyagerAccessSetup.exe\n")

    def test_a_zip_left_by_an_older_build_is_removed(self):
        (self.out / "VoyagerAccessMod.zip").write_bytes(b"old")
        (self.out / "VoyagerAccessMod.zip.sha256").write_text("x  VoyagerAccessMod.zip\n")
        self.assertNotIn("VoyagerAccessMod.zip", self.run_step())
        self.assertFalse((self.out / "VoyagerAccessMod.zip.sha256").exists())

    def run_step_raw(self, *extra):
        cmd = [PWSH, "-NoProfile", "-NonInteractive", "-File", str(STEP),
               "-Out", str(self.out), "-Scripts", str(self.scripts), "-Stage", str(self.stage), *extra]
        return subprocess.run(cmd, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=120)

    def test_a_zip_that_cannot_be_removed_fails_the_step(self):
        # Fable re-review 2026-11-11: the removal used SilentlyContinue and
        # never checked, so with the old zip held open the step said "not
        # built", exited 0, and left the zip for the upload. A real open
        # handle with no sharing makes Windows refuse the delete.
        import ctypes
        from ctypes import wintypes
        old = self.out / "VoyagerAccessMod.zip"
        old.write_bytes(b"old")
        CreateFileW = ctypes.windll.kernel32.CreateFileW
        CreateFileW.restype = wintypes.HANDLE
        handle = CreateFileW(str(old), 0x80000000, 0, None, 3, 0x80, None)   # GENERIC_READ, no sharing
        self.assertNotEqual(handle, wintypes.HANDLE(-1).value)
        try:
            p = self.run_step_raw()
        finally:
            ctypes.windll.kernel32.CloseHandle(handle)
        self.assertNotEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIn("VoyagerAccessMod.zip", p.stdout + p.stderr)

    def test_clean_only_removes_the_old_zip_and_writes_nothing(self):
        # Fable re-review 2026-11-11: the step ran only at the END of
        # build.ps1, so a build that failed earlier left the old zip in
        # dist\installer. build.ps1 now runs -CleanOnly first.
        (self.out / "VoyagerAccessSetup.exe").unlink()        # nothing built yet
        (self.out / "VoyagerAccessMod.zip").write_bytes(b"old")
        (self.out / "VoyagerAccessMod.zip.sha256").write_text("x  VoyagerAccessMod.zip\n")
        self.assertEqual(self.run_step("-CleanOnly"), [])

    def test_live_patching_flag_brings_the_zip_back(self):
        # Negative twin: the switch still makes all four files.
        self.assertEqual(self.run_step("-LivePatching"),
                         ["VoyagerAccessMod.zip", "VoyagerAccessMod.zip.sha256",
                          "VoyagerAccessSetup.exe", "VoyagerAccessSetup.exe.sha256"])


class BuildWiringTests(unittest.TestCase):
    def test_build_uses_the_step_and_passes_the_switch_through(self):
        self.assertRegex(BUILD, r"param\(\s*\[switch\]\$LivePatching\s*\)")
        self.assertIn("installer\\release-files.ps1", BUILD)
        self.assertIn("-LivePatching:$LivePatching", BUILD)

    def test_build_cleans_the_old_zip_before_building_anything(self):
        clean = BUILD.find("-CleanOnly")
        self.assertGreaterEqual(clean, 0, "build.ps1 does not run release-files.ps1 -CleanOnly")
        # The commands themselves (the header comment also names some steps).
        for first_build_step in ("py -3.11 -m unittest discover", "-File installer\\build_native.ps1",
                                 "py -3.11 installer\\build_payload.py", "py -3.11 -m PyInstaller"):
            at = BUILD.find(first_build_step)
            self.assertGreaterEqual(at, 0, first_build_step)
            self.assertLess(clean, at, first_build_step)

    def test_build_no_longer_writes_the_zip_itself(self):
        self.assertNotIn("Compress-Archive", BUILD)


if __name__ == "__main__":
    unittest.main()
