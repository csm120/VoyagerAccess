"""Every Ctrl+F1 line is in the translation inventory and in all seven tables.

Fable review, 2026-11-10 (mod low 20): the Control F11 line and the
reworded E line were in no table, so in another language the first stayed
English and the second came out mixed. tools/check_translations.py checks
the tables against docs/translation/phrases_en.txt but not the code
against the inventory, so this reads hotkeys.lua's own groups (through
lupa) and checks each line.
"""
import unittest
from pathlib import Path

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "mod" / "VoyagerAccess" / "Scripts"
PHRASES = ROOT / "docs" / "translation" / "phrases_en.txt"
LANGS = ("de", "es", "fr", "ja", "pl", "ru", "zh_Hans")


@unittest.skipIf(lupa is None, "lupa not installed")
class HotkeysTranslatedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        lua.execute('package.preload["speech"] = function() return { say = function() end } end')
        M = lua.execute("return (require('hotkeys'))")
        groups = None
        for i in range(1, 256):
            got = lua.eval("debug.getupvalue")(M.toggle, i)
            if not got or got[0] is None:
                break
            if got[0] == "build":
                build = got[1]
                for j in range(1, 256):
                    g = lua.eval("debug.getupvalue")(build, j)
                    if not g or g[0] is None:
                        break
                    if g[0] == "GROUPS":
                        groups = g[1]
        cls.lines = []
        for g in groups.values():
            cls.lines.append(g[1])
            cls.lines.extend(g[2].values())
        cls.inventory = {l.split("\t")[0] for l in PHRASES.read_text(encoding="utf-8").splitlines()
                         if l and not l.startswith("#")}
        cls.tables = {}
        for lang in LANGS:
            t = lupa.LuaRuntime().execute((SCRIPTS / f"tr_{lang}.lua").read_text(encoding="utf-8"))
            cls.tables[lang] = set(t.keys())

    def test_lines_found(self):
        self.assertGreater(len(self.lines), 40)

    def test_every_line_in_the_inventory(self):
        missing = [l for l in self.lines if l not in self.inventory]
        self.assertEqual(missing, [])

    def test_every_line_in_every_table(self):
        for lang, keys in self.tables.items():
            with self.subTest(lang=lang):
                self.assertEqual([l for l in self.lines if l not in keys], [])


if __name__ == "__main__":
    unittest.main()
