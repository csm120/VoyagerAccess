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

    def test_is_installed(self):
        self.assertFalse(modfiles.is_installed(self.data, "4054540"))
        self.install()
        self.assertTrue(modfiles.is_installed(self.data, "4054540"))


if __name__ == "__main__":
    unittest.main()
