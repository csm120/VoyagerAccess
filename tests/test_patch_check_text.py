"""tools/patch_check.py: the text diff and the replaced-screen hint."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
try:
    import patch_check  # noqa: E402
except ImportError:   # the public copy leaves the dump tools out
    patch_check = None


@unittest.skipIf(patch_check is None, "tools/patch_check.py is not in this copy")
class TextDiffTests(unittest.TestCase):
    def test_added_changed_removed(self):
        with tempfile.TemporaryDirectory() as d:
            old, new = Path(d) / "old.txt", Path(d) / "new.txt"
            old.write_text("f.locres\tNS\tA\tSame\nf.locres\tNS\tB\tOld words\nf.locres\tNS\tC\tGone\n",
                           encoding="utf-8")
            new.write_text("f.locres\tNS\tA\tSame\nf.locres\tNS\tB\tNew words\n"
                           "f.locres\tNS\tD\tKrenim temporal wave\n", encoding="utf-8")
            added, changed, removed = patch_check.text_diff(patch_check.locres_texts(old),
                                                            patch_check.locres_texts(new))
        self.assertEqual(added, [("NS", "D")])
        self.assertEqual(changed, [("NS", "B")])
        self.assertEqual(removed, [("NS", "C")])

    def test_change_on_a_second_line_is_found(self):
        # A text with a line break goes on over the next physical line (GPT
        # review, 2026-11-25): a change there was lost.
        with tempfile.TemporaryDirectory() as d:
            old, new = Path(d) / "old.txt", Path(d) / "new.txt"
            old.write_text("G.locres\tNS\tR\tSick bay report.\nAssigned hero adds a bonus.\n", encoding="utf-8")
            new.write_text("G.locres\tNS\tR\tSick bay report.\nAssigned hero adds a larger bonus.\n", encoding="utf-8")
            added, changed, removed = patch_check.text_diff(patch_check.locres_texts(old),
                                                            patch_check.locres_texts(new))
        self.assertEqual(changed, [("NS", "R")])

    def test_same_build_is_empty(self):
        t = {("NS", "A"): "x"}
        self.assertEqual(patch_check.text_diff(t, dict(t)), ([], [], []))


@unittest.skipIf(patch_check is None, "tools/patch_check.py is not in this copy")
class ReplacedScreenTests(unittest.TestCase):
    def test_new_version_is_named(self):
        got = patch_check.replaced_screens({"WBP_RoomManagementV3_C", "WBP_Krenim_C"},
                                           {"WBP_RoomManagementV2_C": ["rooms.lua"]})
        self.assertEqual(got, {"WBP_RoomManagementV3_C": ["WBP_RoomManagementV2_C"]})

    def test_unrelated_class_is_not(self):
        self.assertEqual(patch_check.replaced_screens({"WBP_Krenim_C"}, {"WBP_RoomManagementV2_C": []}), {})


if __name__ == "__main__":
    unittest.main()
