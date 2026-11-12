"""F1 and Ctrl+F1 name the keys docs/keyboard.md documents.

Fable review, 2026-11-10 (mod low 19): F1 in the ship view left out J and
Page Up and Page Down (Ctrl+F1 has them); Ctrl+F1's Away missions group
left out Left and Right, or Page Up and Page Down, between tasks (0.3.89);
neither had Backspace on a filled away team slot (0.4.2). F1's text is
translated sentence by sentence, so each ship-view sentence must be in the
inventory and in every table. Runs the real help.lua and hotkeys.lua under
lupa.
"""
import re
import unittest

from tests.test_hotkeys_translated import LANGS, PHRASES, SCRIPTS, HotkeysTranslatedTests, lupa


@unittest.skipIf(lupa is None, "lupa not installed")
class KeyListTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        HotkeysTranslatedTests.setUpClass()
        cls.lines = HotkeysTranslatedTests.lines
        cls.inventory = HotkeysTranslatedTests.inventory
        cls.tables = HotkeysTranslatedTests.tables
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        lua.execute('''
            said = nil
            package.preload["speech"] = function() return { say = function(t) said = t end } end
            package.preload["awaymission"] = function() return { keys_active = function() return false end } end
            package.preload["techtree"] = function() return { open = function() return false end } end
            for _, m in ipairs({ "screen", "crumb", "keys", "popups", "focus", "dialogue", "tr", "text", "hints" }) do
                package.preload[m] = function() return setmetatable({}, { __index = function() return function() end end }) end
            end
            function FindAllOf() return {} end
            function FindFirstOf() return nil end
            function StaticFindObject() return nil end
            function RegisterHook() end
            function NotifyOnNewObject() end
            function ExecuteInGameThread(fn) fn() end
            function ExecuteInGameThreadWithDelay() end
            function LoopAsync() end
        ''')
        help_ = lua.execute("return (require('help'))")
        help_.context = lambda: "ship"
        for i in range(1, 256):
            got = lua.eval("debug.getupvalue")(help_.say_help, i)
            if not got or got[0] is None:
                break
            if got[0] == "overview_open":
                lua.eval("debug.setupvalue")(help_.say_help, i, lua.eval("function() return false end"))
        help_.say_help()
        cls.ship = lua.globals().said.replace(" Control F1 lists every key.", "")

    def test_f1_ship_view_names_j_and_page_keys(self):
        self.assertIn("J ", self.ship)
        self.assertIn("Page Up and Page Down", self.ship)

    def test_ctrl_f1_away_names_task_jumps_and_backspace(self):
        away = " ".join(l for l in self.lines if "task" in l.lower() or "slot" in l.lower())
        self.assertIn("Page Up and Page Down", away)
        self.assertIn("Backspace", away)

    def test_ship_view_sentences_are_translated(self):
        # The sentences that name these keys (the others were checked when
        # they were written; one table key can hold two sentences).
        sentences = [s.strip() for s in re.findall(r"[^.]+\.", self.ship) if "Page Up" in s or s.strip().startswith("J ")]
        self.assertEqual(len(sentences), 2, sentences)
        missing = [s for s in sentences if s not in self.inventory]
        self.assertEqual(missing, [])
        for lang, keys in self.tables.items():
            with self.subTest(lang=lang):
                self.assertEqual([s for s in sentences if s not in keys], [])


if __name__ == "__main__":
    unittest.main()
