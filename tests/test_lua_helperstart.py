"""helperstart.lua: the mod starts the helper when none is running.

Casey (2026-10-29): "the mod should start the helper whenever possible".
The helper writes the time to helper-alive.txt every second while it
serves; when that is missing or stale and the mod has been up long enough
for a normal launch, the mod starts the installed helper with --attach.
Runs the real helperstart.lua under lupa with the clock and files stubbed.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

LUA = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts" / "helperstart.lua"


@unittest.skipIf(lupa is None, "lupa not installed")
class HelperStartTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            NOW = 1000
            ALIVE = nil          -- the helper-alive.txt contents, nil while missing
            EXE = true           -- the installed helper exists
            started = {}
            closed = 0
            executed = 0
            os.time = function() return NOW end
            os.getenv = function() return "C:\\\\Users\\\\x\\\\AppData\\\\Local" end
            os.execute = function(cmd) executed = executed + 1 return true end
            native = 0
            LOADLIB = false
            package.loadlib = function(path, fn)
                LOADLIB_PATH = path
                if not LOADLIB then return nil, "not found" end
                return function() native = native + 1 return 0 end
            end
            io.popen = function(cmd, mode)
                started[#started + 1] = cmd
                POPEN_MODE = mode
                return { close = function() closed = closed + 1 end }
            end
            print = function() end
            io.open = function(p, m)
                if p:find("helper%-alive") then
                    if not ALIVE then return nil end
                    return { read = function() return ALIVE end, close = function() end }
                end
                if p:find("VoyagerAccess%.exe") then
                    if not EXE then return nil end
                    return { close = function() end }
                end
                return nil
            end
        ''')
        # dofile, so debug.getinfo sees the real ...\Scripts\helperstart.lua.
        self.M = self.lua.eval("dofile")(str(LUA))
        self.M.loaded()
        self.g = self.lua.globals()

    def at(self, t, alive=None):
        self.g.NOW = t
        self.g.ALIVE = alive
        self.M.check()
        return len(self.g.started)

    def test_nothing_during_the_grace_after_the_mod_loads(self):
        self.assertEqual(self.at(1010), 0)

    def test_a_missing_helper_is_started_with_attach(self):
        self.assertEqual(self.at(1020), 1)
        cmd = self.g.started[1]
        self.assertIn("VoyagerAccess.exe", cmd)
        self.assertIn("--attach", cmd)

    def test_a_living_helper_is_left_alone(self):
        self.assertEqual(self.at(1020, alive="1018"), 0)

    def test_a_stale_helper_counts_as_missing(self):
        self.assertEqual(self.at(1030, alive="1015"), 1)

    def test_tries_are_a_minute_apart_and_at_most_three(self):
        self.at(1020)
        self.assertEqual(self.at(1040), 1)
        self.assertEqual(self.at(1081), 2)
        self.assertEqual(self.at(1142), 3)
        self.assertEqual(self.at(1300), 3)

    def test_started_through_popen_without_a_console_flash(self):
        # os.execute's console made NVDA say "Terminal ... cmd.exe" and took
        # focus; io.popen did neither (VM, 2026-10-29).
        self.at(1020)
        self.assertEqual(self.g.executed, 0)
        self.assertEqual(self.g.POPEN_MODE, "w")

    def test_the_pipe_is_closed_later_not_at_once(self):
        # Closing at once held the game thread 5 to 6 s while cmd.exe exited;
        # 15 s later the close took a quarter of a millisecond (VM).
        self.at(1020)
        self.assertEqual(self.g.closed, 0)
        self.at(1030)
        self.assertEqual(self.g.closed, 0)
        self.at(1041, alive="1040")
        self.assertEqual(self.g.closed, 1)

    def test_voystart_dll_is_used_when_present(self):
        # cmd.exe still got a console with io.popen ("cmd.exe" said once in
        # the VM); voystart.dll starts the helper with no window at all.
        self.g.LOADLIB = True
        self.at(1020)
        self.assertEqual(self.g.native, 1)
        self.assertEqual(len(self.g.started), 0)
        self.assertTrue(str(self.g.LOADLIB_PATH).endswith("voystart.dll"))

    def test_no_installed_helper_means_no_try(self):
        self.g.EXE = False
        self.assertEqual(self.at(1020), 0)


if __name__ == "__main__":
    unittest.main()
