"""main.lua: one module failing to install leaves the rest, keys first, working.

Before 2026-10-29 the installs were not guarded and keys.install() came
near the end, so any earlier module's error left keys dead after "Voyager
Access loaded" had been spoken (the WFH session's reliability review).
Runs the real main.lua under lupa with every module stubbed.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

MAIN_LUA = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts" / "main.lua"

MODULES = ["focus", "dialogue", "story", "popups", "system", "quest", "help", "resources", "view",
           "awaymission", "whatsnew", "hotkeys", "credits", "techtree", "combat", "ship", "events",
           "language", "keys"]


@unittest.skipIf(lupa is None, "lupa not installed")
class MainInstallTests(unittest.TestCase):
    def run_main(self, failing):
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
            installed, said = {}, {}
            os.getenv = function() return "Z:\\\\no-such-folder" end
            LoopInGameThreadWithDelay = function() end
            package.preload["speech"] = function() return {
                reset = function() end,
                say = function(t) said[#said + 1] = t end } end
            package.preload["tr"] = function() return {
                fill = function(t, s) return (t:gsub("{s}", s)) end } end
            package.preload["reload"] = function() return function() end end
            package.preload["devcmd"] = function() return function() end end
        ''')
        for name in MODULES:
            lua.execute('package.preload["%s"] = function() return { install = function() '
                        '%s installed[#installed + 1] = "%s" end } end'
                        % (name, 'error("broken")' if name == failing else "", name))
        lua.execute(MAIN_LUA.read_text(encoding="utf-8"))
        g = lua.globals()
        return list(g.installed.values()), list(g.said.values())

    def test_keys_install_even_when_an_earlier_module_fails(self):
        installed, said = self.run_main("focus")
        self.assertIn("keys", installed)

    def test_the_other_modules_still_install(self):
        installed, said = self.run_main("combat")
        self.assertIn("ship", installed)
        self.assertIn("language", installed)

    def test_the_failure_is_spoken_with_the_module_name(self):
        installed, said = self.run_main("combat")
        self.assertTrue(any("combat" in s for s in said), said)

    def test_nothing_extra_is_said_when_all_install(self):
        installed, said = self.run_main(None)
        self.assertEqual(said, ["Voyager Access loaded"])
        self.assertEqual(sorted(installed), sorted(MODULES))


if __name__ == "__main__":
    unittest.main()
