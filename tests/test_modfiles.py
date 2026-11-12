import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager import modfiles  # noqa: E402


class ModFilesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.game = root / "Win64"
        self.game.mkdir()
        (self.game / "STVoyager-Win64-Shipping.exe").write_bytes(b"game")
        self.payload = root / "payload"
        self.data = root / "data"
        self.files = {"dwmapi.dll": b"proxy", "ue4ss/UE4SS.dll": b"ue4ss",
                      "ue4ss/Mods/VoyagerAccess/Scripts/main.lua": b"-- v1"}
        self.write(self.payload, self.files)
        # The real check would see the game if Casey is playing.
        self._real = modfiles.game_is_running
        modfiles.game_is_running = lambda: False

    def tearDown(self):
        modfiles.game_is_running = self._real
        self.tmp.cleanup()

    def write(self, base, files):
        for rel, data in files.items():
            p = base / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)

    def tree(self):
        return sorted(p.relative_to(self.game).as_posix() for p in self.game.rglob("*"))

    def install(self):
        return modfiles.install(self.game, self.payload, self.data, "4054540")

    def test_install_then_uninstall_leaves_game_as_it_was(self):
        before = self.tree()
        self.install()
        self.assertEqual((self.game / "ue4ss/Mods/VoyagerAccess/Scripts/main.lua").read_bytes(), b"-- v1")
        modfiles.uninstall(self.game, self.data, "4054540")
        self.assertEqual(self.tree(), before)

    def test_replaced_file_is_backed_up_and_restored(self):
        (self.game / "dwmapi.dll").write_bytes(b"someone else's")
        self.install()
        self.assertEqual((self.game / "dwmapi.dll").read_bytes(), b"proxy")
        modfiles.uninstall(self.game, self.data, "4054540")
        self.assertEqual((self.game / "dwmapi.dll").read_bytes(), b"someone else's")

    def test_other_mods_in_ue4ss_folder_survive_uninstall(self):
        self.write(self.game, {"ue4ss/Mods/OtherMod/main.lua": b"x"})
        self.install()
        modfiles.uninstall(self.game, self.data, "4054540")
        self.assertTrue((self.game / "ue4ss/Mods/OtherMod/main.lua").exists())

    def test_update_overwrites_own_files_and_removes_dropped_ones(self):
        self.install()
        (self.payload / "ue4ss/Mods/VoyagerAccess/Scripts/main.lua").write_bytes(b"-- v2")
        (self.payload / "ue4ss/UE4SS.dll").unlink()
        self.install()
        self.assertEqual((self.game / "ue4ss/Mods/VoyagerAccess/Scripts/main.lua").read_bytes(), b"-- v2")
        self.assertFalse((self.game / "ue4ss/UE4SS.dll").exists())
        # Our own earlier copy must not have been "backed up" and restored.
        modfiles.uninstall(self.game, self.data, "4054540")
        self.assertEqual(self.tree(), ["STVoyager-Win64-Shipping.exe"])

    def test_refuses_while_game_running(self):
        with self.assertRaises(modfiles.GameRunning):
            modfiles.install(self.game, self.payload, self.data, "4054540", game_running=lambda: True)
        self.assertEqual(self.tree(), ["STVoyager-Win64-Shipping.exe"])

    def test_uninstall_without_manifest_does_nothing(self):
        self.write(self.game, {"dwmapi.dll": b"not ours"})
        modfiles.uninstall(self.game, self.data, "4054540")
        self.assertTrue((self.game / "dwmapi.dll").exists())

    def test_ue4ss_log_in_created_folder_is_cleared(self):
        before = self.tree()
        self.install()
        self.write(self.game, {"ue4ss/UE4SS.log": b"log"})
        modfiles.uninstall(self.game, self.data, "4054540")
        self.assertEqual(self.tree(), before)

    def test_log_in_folder_that_was_already_there_is_kept(self):
        self.write(self.game, {"ue4ss/UE4SS.log": b"theirs"})
        self.install()
        modfiles.uninstall(self.game, self.data, "4054540")
        self.assertTrue((self.game / "ue4ss/UE4SS.log").exists())

    def test_version_is_recorded(self):
        modfiles.install(self.game, self.payload, self.data, "4054540", version="0.2.0")
        self.assertEqual(modfiles.load_manifest(self.data, "4054540")["version"], "0.2.0")

    def test_uninstall_all_uses_recorded_game_folder(self):
        before = self.tree()
        self.install()
        modfiles.uninstall_all(self.data)
        self.assertEqual(self.tree(), before)
        self.assertFalse(modfiles.is_installed(self.data, "4054540"))

    def test_uninstall_after_the_game_folder_was_deleted(self):
        # Pre-merge review 2026-11-10, M2: a backed-up file could not be
        # copied back into a folder that is gone, so uninstall failed every
        # time. Nothing is left to remove; the record goes.
        (self.game / "dwmapi.dll").write_bytes(b"someone else's")
        self.install()
        import shutil
        shutil.rmtree(self.game)
        modfiles.uninstall_all(self.data)
        self.assertFalse(modfiles.is_installed(self.data, "4054540"))

    def test_is_installed(self):
        self.assertFalse(modfiles.is_installed(self.data, "4054540"))
        self.install()
        self.assertTrue(modfiles.is_installed(self.data, "4054540"))

    # Fable review 2026-11-10, helper finding 3: an install cut off part way
    # left no manifest, so the next install backed up the mod's own files as
    # another mod's and uninstall put them back.
    def interrupted_install(self, after=1):
        real = modfiles.shutil.copy2
        copies = []

        def flaky(src, dst, *a, **k):
            if Path(src).is_relative_to(self.payload):
                if len(copies) >= after:
                    raise PermissionError("locked by antivirus")
                copies.append(dst)
            return real(src, dst, *a, **k)
        modfiles.shutil.copy2 = flaky
        try:
            with self.assertRaises(OSError):
                self.install()
        finally:
            modfiles.shutil.copy2 = real

    def test_interrupted_install_then_uninstall_leaves_game_as_it_was(self):
        before = self.tree()
        self.interrupted_install()
        self.install()
        modfiles.uninstall(self.game, self.data, "4054540")
        self.assertEqual(self.tree(), before)

    def test_interrupted_install_still_restores_another_mods_file(self):
        # Negative twin: a file that really was someone else's is kept safe.
        (self.game / "dwmapi.dll").write_bytes(b"someone else's")
        self.interrupted_install()
        self.install()
        modfiles.uninstall(self.game, self.data, "4054540")
        self.assertEqual((self.game / "dwmapi.dll").read_bytes(), b"someone else's")

    # Pre-merge review 2026-11-10, L2: a new file half written when the
    # install was cut off was in neither list, so the next install backed it
    # up as another mod's and uninstall put the truncated file back.
    def test_half_copied_new_file_is_not_kept_as_another_mods(self):
        before = self.tree()
        real = modfiles.shutil.copy2

        def half(src, dst, *a, **k):
            if Path(src).is_relative_to(self.payload) and Path(dst).name == "dwmapi.dll":
                Path(dst).write_bytes(b"pr")
                raise OSError("cut off")
            return real(src, dst, *a, **k)
        modfiles.shutil.copy2 = half
        try:
            with self.assertRaises(OSError):
                self.install()
        finally:
            modfiles.shutil.copy2 = real
        self.install()
        modfiles.uninstall(self.game, self.data, "4054540")
        self.assertEqual(self.tree(), before)

    # Pre-merge review 2026-11-10, L3: the manifest was rewritten in place
    # about twice per file, so a kill during a write left it truncated and
    # every mod file then looked like another mod's.
    def test_manifest_write_cut_off_leaves_the_old_manifest(self):
        self.install()
        good = modfiles.load_manifest(self.data, "4054540")
        real = Path.write_text

        def cut(path, data, *a, **k):
            if path.parent.name == "installs":
                real(path, data[:5], *a, **k)
                raise OSError("killed")
            return real(path, data, *a, **k)
        Path.write_text = cut
        try:
            with self.assertRaises(OSError):
                self.install()
        finally:
            Path.write_text = real
        self.assertEqual(modfiles.load_manifest(self.data, "4054540"), good)
        self.assertEqual(sorted(p.name for p in (self.data / "installs").iterdir()), ["4054540.json"])

    def test_manifest_still_written_whole(self):
        # Negative twin: a normal install still records every file.
        self.install()
        self.assertEqual(sorted(modfiles.load_manifest(self.data, "4054540")["files"]), sorted(self.files))


if __name__ == "__main__":
    unittest.main()
