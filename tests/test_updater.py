import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager import updater  # noqa: E402


class VersionTests(unittest.TestCase):
    def test_newer(self):
        self.assertTrue(updater.is_newer("v0.2.0", "0.1.0"))
        self.assertTrue(updater.is_newer("0.1.10", "0.1.9"))
        self.assertTrue(updater.is_newer("1.0", "0.9.9"))
        self.assertFalse(updater.is_newer("0.1.0", "0.1.0"))
        self.assertFalse(updater.is_newer("v0.1", "0.1.0"))
        self.assertFalse(updater.is_newer("0.0.9", "0.1.0"))
        self.assertFalse(updater.is_newer("garbage", "0.1.0"))


class FeedTests(unittest.TestCase):
    """The whole check and download through a local file:// feed."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.setup = root / "VoyagerAccessSetup.exe"
        self.setup.write_bytes(b"new installer")
        digest = hashlib.sha256(b"new installer").hexdigest()
        (root / "VoyagerAccessSetup.exe.sha256").write_text(digest + "  VoyagerAccessSetup.exe\n")
        self.feed = root / "latest.json"
        self.write_feed("v0.2.0", draft=False, prerelease=False)
        self.out = root / "download"

    def tearDown(self):
        self.tmp.cleanup()

    def write_feed(self, tag, draft, prerelease, names=("VoyagerAccessSetup.exe", "VoyagerAccessSetup.exe.sha256")):
        root = Path(self.tmp.name)
        assets = [{"name": n, "browser_download_url": (root / n).as_uri()} for n in names]
        self.feed.write_text(json.dumps({"tag_name": tag, "draft": draft, "prerelease": prerelease,
                                         "assets": assets}))

    def check(self, current="0.1.0"):
        return updater.check(self.feed.as_uri(), current)

    def test_finds_newer_release(self):
        release = self.check()
        self.assertEqual(release.version, "0.2.0")

    def test_same_version_is_no_update(self):
        self.assertIsNone(self.check(current="0.2.0"))

    def test_prerelease_and_draft_are_ignored(self):
        self.write_feed("v0.2.0", draft=False, prerelease=True)
        self.assertIsNone(self.check())
        self.write_feed("v0.2.0", draft=True, prerelease=False)
        self.assertIsNone(self.check())

    def test_missing_installer_asset_is_no_update(self):
        self.write_feed("v0.2.0", False, False, names=("Other.zip",))
        self.assertIsNone(self.check())

    def test_download_verifies_checksum(self):
        path = updater.download(self.check(), self.out)
        self.assertEqual(path.read_bytes(), b"new installer")

    def test_checksum_mismatch_refuses(self):
        self.setup.write_bytes(b"tampered")
        with self.assertRaises(updater.UpdateError):
            updater.download(self.check(), self.out)
        self.assertFalse((self.out / "VoyagerAccessSetup.exe").exists())

    def test_missing_checksum_refuses(self):
        self.write_feed("v0.2.0", False, False, names=("VoyagerAccessSetup.exe",))
        with self.assertRaises(updater.UpdateError):
            updater.download(self.check(), self.out)

    def test_unreachable_feed_is_no_update(self):
        self.assertIsNone(updater.check((Path(self.tmp.name) / "nope.json").as_uri(), "0.1.0"))


class MarkerTests(unittest.TestCase):
    def test_marker_reports_once(self):
        with tempfile.TemporaryDirectory() as d:
            marker = Path(d) / "pending-update.json"
            updater.write_marker(marker, "0.2.0")
            self.assertEqual(updater.read_marker(marker, "0.2.0"), "updated")
            self.assertIsNone(updater.read_marker(marker, "0.2.0"))

    def test_marker_reports_failure(self):
        with tempfile.TemporaryDirectory() as d:
            marker = Path(d) / "pending-update.json"
            updater.write_marker(marker, "0.2.0")
            self.assertEqual(updater.read_marker(marker, "0.1.0"), "failed")


if __name__ == "__main__":
    unittest.main()
