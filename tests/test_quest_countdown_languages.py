"""quest.lua: a goal's own cycle countdown is not a change, in any language.

Fable review, 2026-11-10 (mod finding 4): the rule for a countdown inside a
goal was keyed on the English "within", so in German Scorpion's goal
"Schließe alle folgenden Aufgaben innerhalb von 36 ZYKLEN ab" was said as
"Changed: ..." on every cycle. Runs the real quest.lua and text.lua under
lupa.
"""
import unittest

from tests.test_quest_changes import QUEST, lupa

SCRIPTS = QUEST.parent


@unittest.skipIf(lupa is None, "lupa not installed")
class CountdownLanguageTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime()
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute('''
package.preload["speech"] = function() return { say = function() end } end
package.preload["screen"] = function() return {} end
package.preload["popups"] = function() return {} end
package.preload["crumb"] = function() return { at = function() end } end
''')
        self.q = self.lua.execute(QUEST.read_text(encoding="utf-8"))
        self.mk = self.lua.eval("function(name, g) return { { name = name, goals = { g } } } end")

    def changes(self, a, b):
        return self.q.changes(self.mk("Skorpion", a), self.mk("Skorpion", b))

    def test_german_countdown_is_not_a_change(self):
        self.assertIsNone(self.changes(
            "Schließe alle folgenden Aufgaben innerhalb von 36 ZYKLEN ab",
            "Schließe alle folgenden Aufgaben innerhalb von 35 ZYKLEN ab"))

    def test_japanese_countdown_is_not_a_change(self):
        self.assertIsNone(self.changes("36サイクル以内にすべてのタスクを完了する",
                                       "35サイクル以内にすべてのタスクを完了する"))

    def test_english_count_without_comma_is_not_a_change(self):
        self.assertIsNone(self.changes("Survive. 12 cycles left.", "Survive. 11 cycles left."))

    def test_other_number_change_is_still_said(self):
        # Negative twin: a number that is not a cycle count still changes.
        said = self.changes("-5 NAHRUNG pro Zyklus", "-10 NAHRUNG pro Zyklus")
        self.assertIsNotNone(said)
        self.assertIn("-10", said)


if __name__ == "__main__":
    unittest.main()
