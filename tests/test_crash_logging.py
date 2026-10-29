"""An uncaught exception anywhere in the helper reaches helper.log.

Before 2026-10-29 a crash's traceback went nowhere (a frozen exe has no
console), so a player who lost speech left no trace for a report.
"""
import logging
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager import app  # noqa: E402


class CrashLoggingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old = (sys.excepthook, threading.excepthook, list(app.log.handlers))
        p = mock.patch.object(app, "DATA_DIR", Path(self.tmp.name))
        p.start()
        self.addCleanup(p.stop)
        app.setup_logging()

    def tearDown(self):
        for h in app.log.handlers:
            if h not in self.old[2]:
                h.close()
        app.log.handlers[:] = self.old[2]
        sys.excepthook, threading.excepthook = self.old[0], self.old[1]
        self.tmp.cleanup()

    def log_text(self):
        for h in app.log.handlers:
            h.flush()
        return (Path(self.tmp.name) / "helper.log").read_text(encoding="utf-8")

    def test_main_thread_crash_is_logged(self):
        try:
            raise ValueError("main thread broke")
        except ValueError:
            sys.excepthook(*sys.exc_info())
        self.assertIn("main thread broke", self.log_text())

    def test_other_thread_crash_is_logged(self):
        t = threading.Thread(target=lambda: (_ for _ in ()).throw(KeyError("key thread broke")), name="t1")
        with mock.patch("sys.stderr"):
            t.start()
            t.join()
        self.assertIn("key thread broke", self.log_text())


if __name__ == "__main__":
    unittest.main()
