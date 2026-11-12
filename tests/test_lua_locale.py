"""Game text matching must not depend on the C locale the game runs under.

Fable review, 2026-11-10 (mod finding 1): Lua's %s, %w and %a test single
bytes through the C runtime's locale. Under "C" a Russian, Japanese or
Chinese text block has no %w and popups.plain dropped it; under code page
1252 or 1251 byte 0xA0 is %s, so the whitespace clean-up broke "voilà"
(C3 A0) and cut the last byte off "СЕКТОР" (Р is D0 A0). Which locale the
game uses is not known (Needs VM verification: print(os.setlocale(nil,
"ctype")) in the live game), so each check here runs under several, and
each run first proves the locale really took effect.

Runs the real speech.lua and popups.lua under lupa.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

# Locale name, and whether byte 0xA0 is %s under it (the proof it took effect).
LOCALES = [("C", False), ("English_United States.1252", True), ("Russian_Russia.1251", True),
           (".UTF-8", False)]

STUBS = rb"""
written = {}
print = function() end
package.preload["tr"] = function()
    return { line = function(s) return s end, word = function(s) return s end,
             fill = function(s) return s end, lower = function(s) return s end }
end
package.preload["screen"] = function() return { shown = function() return true end } end
package.preload["crumb"] = function() return setmetatable({}, { __index = function() return function() end end }) end
io.open = function(p, m)
    return { write = function(self, ...) for _, s in ipairs({...}) do written[#written + 1] = s end return self end,
             close = function() end, flush = function() end, seek = function() return 0 end,
             read = function() return nil end, lines = function() return function() return nil end end }
end
function FindAllOf() return {} end
function StaticFindObject() return nil end
function RegisterHook() end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay(_, fn) fn() end
function LoopAsync() end
"""


def runtime(locale):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True, encoding=None)
    got = lua.execute(b'return os.setlocale(...,"ctype")', locale.encode())
    return lua, got


@unittest.skipIf(lupa is None, "lupa not installed")
class LocaleTests(unittest.TestCase):
    def tearDown(self):
        # Put the process back on the locale Python started with.
        lua = lupa.LuaRuntime(encoding=None)
        lua.execute(b'os.setlocale("", "ctype")')

    def each(self):
        """(locale, Lua runtime) for each locale this machine has, with the
        scripts on its path. The C locale is process-wide, so each runtime
        is made and used before the next locale is set. Each is checked
        first: the locale really applies to this Lua, else the test would
        prove nothing."""
        ran = 0
        for name, nbsp_is_space in LOCALES:
            lua, got = runtime(name)
            if got is None:
                continue            # not on this machine
            self.assertEqual(lua.execute(b'return ("\\160"):find("%s") ~= nil'), nbsp_is_space, name)
            lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path".encode())
            lua.execute(STUBS)
            ran += 1
            yield name, lua
        self.assertGreaterEqual(ran, 3, "too few locales to compare")

    def said(self, lua, text):
        lua.globals().written = lua.table()
        speech = lua.execute(b"return (require('speech'))")
        speech.say(text.encode("utf-8"), True)
        return b"".join(lua.globals().written.values())

    def test_speech_keeps_letters_with_byte_a0(self):
        for name, lua in self.each():
            with self.subTest(locale=name):
                out = self.said(lua, "Voilà, déjà vu. СЕКТОР")
                self.assertIn("Voilà, déjà vu. СЕКТОР".encode("utf-8"), out)
                out = self.said(lua, "СЕКТОР ,")
                self.assertIn("СЕКТОР,".encode("utf-8"), out)

    def test_speech_still_tidies_ascii_spaces(self):
        # Negative twin: the clean-up itself still happens.
        for name, lua in self.each():
            with self.subTest(locale=name):
                out = self.said(lua, "  One , two .  ")
                self.assertIn(b"One, two.", out)
                self.assertNotIn(b"  ", out)

    def test_plain_keeps_non_latin_text(self):
        for name, lua in self.each():
            popups = lua.execute(b"return (require('popups'))")
            for text in ("Задача", "任务完成", "ミッション", "voilà  à"):
                with self.subTest(locale=name, text=text):
                    want = text.replace("  ", " ").encode("utf-8")
                    self.assertEqual(popups.plain(text.encode("utf-8")), want)

    def test_plain_still_drops_a_lone_symbol(self):
        # Negative twin: an icon's "+" label, and symbol-only text, still go.
        for name, lua in self.each():
            popups = lua.execute(b"return (require('popups'))")
            for text in ("+", " + ", "•", "—", "3"):
                with self.subTest(locale=name, text=text):
                    want = b"3" if text == "3" else b""
                    self.assertEqual(popups.plain(text.encode("utf-8")), want)


if __name__ == "__main__":
    unittest.main()
