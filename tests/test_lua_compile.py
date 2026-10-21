"""Every mod script compiles (lupa's Lua). A syntax error stops the whole
mod in the game, and nothing else here loads every file: a declaration moved
below its first use is caught by review only, but a missing "end" or a stray
character is caught here. Skipped when lupa is not installed."""
import unittest
from pathlib import Path

try:
    import lupa
except ImportError:
    lupa = None

SCRIPTS = Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"


@unittest.skipIf(lupa is None, "lupa not installed")
class LuaCompileTests(unittest.TestCase):
    def test_every_script_compiles(self):
        lua = lupa.LuaRuntime()
        check = lua.eval('function(s, n) local f, e = load(s, "=" .. n) return e or "ok" end')
        files = sorted(SCRIPTS.glob("*.lua"))
        self.assertGreater(len(files), 30)
        bad = {}
        for f in files:
            r = check(f.read_text(encoding="utf-8"), f.name)
            if r != "ok":
                bad[f.name] = r
        self.assertEqual(bad, {})

    def test_a_broken_script_is_caught(self):
        lua = lupa.LuaRuntime()
        check = lua.eval('function(s) local f, e = load(s) return e or "ok" end')
        self.assertNotEqual(check("local function f() return 1"), "ok")


if __name__ == "__main__":
    unittest.main()
