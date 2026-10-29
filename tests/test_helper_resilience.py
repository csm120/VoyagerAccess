"""The helper keeps speaking when one line, click or key handler fails.

A player who loses speech mid-game cannot report it, and before 2026-10-29
any exception in _serve_loop (Tolk, a click, a mouse move, on_keys) ended
speech for the rest of the session (the WFH session's reliability review).
"""
import queue
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from voyager import helper  # noqa: E402


class FakeTailer:
    def __init__(self, batches):
        self.batches = list(batches)

    def read_lines(self):
        return self.batches.pop(0) if self.batches else []


class FakeTolk:
    def __init__(self, fail_on):
        self.fail_on = fail_on
        self.said = []

    def say(self, text, interrupt):
        if text == self.fail_on:
            raise OSError("Tolk failed")
        self.said.append(text)


def run_loop(tolk, tailer, on_keys=None, pressed=None):
    checks = []

    def keep_going():
        checks.append(1)
        return len(checks) < 3      # about two seconds of loop

    q = queue.Queue()
    for p in pressed or []:
        q.put(p)
    helper._serve_loop(tolk, tailer, keep_going, on_keys, lambda t: None,
                       lambda what, fn, *a: fn(*a), q)


class ServeLoopResilienceTests(unittest.TestCase):
    def test_a_failing_line_does_not_end_speech(self):
        tolk = FakeTolk(fail_on="boom")
        run_loop(tolk, FakeTailer([["I|boom", "I|after"], ["Q|later"]]))
        self.assertEqual(tolk.said, ["after", "later"])

    def test_a_failing_key_handler_does_not_end_speech(self):
        tolk = FakeTolk(fail_on=None)

        def on_keys(names):
            raise RuntimeError("handler failed")

        run_loop(tolk, FakeTailer([[], ["I|still here"]]), on_keys=on_keys, pressed=[["f12"]])
        self.assertEqual(tolk.said, ["still here"])


class SessionCheckResilienceTests(unittest.TestCase):
    def test_a_failing_session_check_does_not_end_speech(self):
        tolk = FakeTolk(fail_on=None)
        calls = []

        def keep_going():
            calls.append(1)
            if len(calls) == 1:
                raise RuntimeError("update check failed")
            return len(calls) < 3

        helper._serve_loop(tolk, FakeTailer([[], ["I|still speaking"]]), keep_going, None,
                           lambda t: None, lambda what, fn, *a: fn(*a), queue.Queue())
        self.assertEqual(tolk.said, ["still speaking"])


if __name__ == "__main__":
    unittest.main()
