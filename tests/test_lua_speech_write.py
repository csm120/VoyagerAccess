"""speech.lua: a speech.txt that cannot be written is logged once.

Before 2026-10-29 every failed write was dropped without a trace, so a
player with no speech left nothing in UE4SS.log to say why (the WFH
session's reliability review). Runs the real speech.lua under lupa.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SPEECH_LUA = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts" / "speech.lua"


@unittest.skipIf(lupa is None, "lupa not installed")
class SpeechWriteTests(unittest.TestCase):
    def load(self, can_open):
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
            printed = {}
            print = function(s) printed[#printed + 1] = s end
            local real_open = io.open
            io.open = function(p, m)
                if CAN_OPEN then return real_open(os.tmpname(), "w") end
                return nil, "Permission denied"
            end
        ''')
        lua.globals().CAN_OPEN = can_open
        M = lua.execute(SPEECH_LUA.read_text(encoding="utf-8"))
        return lua, M

    def test_a_failed_write_is_logged_once(self):
        lua, M = self.load(False)
        M.reset()
        M.reset()
        printed = [p for p in lua.globals().printed.values() if "speech.txt" in p]
        self.assertEqual(len(printed), 1)
        self.assertIn("Permission denied", printed[0])

    def test_a_good_write_logs_nothing(self):
        lua, M = self.load(True)
        M.reset()
        self.assertEqual(len(lua.globals().printed), 0)


if __name__ == "__main__":
    unittest.main()
