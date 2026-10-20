"""tr.lua puts the mod's own English words into the game's language
(firefly82's review, 2026-10-20: "Deck", "Tier", "on" stayed English in the
German game). Runs the real Lua through lupa; skipped when lupa is not
installed."""
import unittest
from pathlib import Path

try:
    import lupa
except ImportError:
    lupa = None

TR = Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts" / "tr.lua"

TABLE = '''
package.preload["tr_de"] = function() return {
    ["Deck {n}"] = "Deck {n}",
    ["decks {n} to {n}"] = "Decks {n} bis {n}",
    ["{n} to {n}"] = "{n} BIS {n}",
    ["{n} of {n}"] = "{n} von {n}",
    ["Not possible: {s}"] = "Nicht möglich: {s}",
    ["Ship view"] = "Schiffsansicht",
    ["on"] = "an",
    ["selected"] = "ausgewählt",
    ["{n} cycles to analyze {s} now"] = "jetzt {2} in {1} Zyklen analysieren",
    ["Press Enter: select"] = "Press Enter: auswählen",
    ["Press Enter: {s}"] = "DOPPELT: {s}",
    ["Not enough: {s}"] = "{s} fehlt",
    ["{s} tab"] = "Registerkarte {s}",
    ["{s} needs {n}"] = "{2} braucht {1}",
    ["Goal: {s}"] = "Ziel: {s}",
    ["up to {n} {s}"] = "bis zu {n} {s}",
    ["to {n} done"] = "{n} fertig",
    ["{s}: none"] = "{s}: keine",
    ["Offensive combat power {n}"] = "Offensive Kampfkraft {n}",
    [", base attack power {n}"] = ", Grundangriffskraft {n}",
} end
package.preload["tr_fr"] = function() return {
    ["on"] = "allumé",
    ["{n} of {n}"] = "{n} sur {n}",
} end
'''


@unittest.skipIf(lupa is None, "lupa not installed")
class TrTests(unittest.TestCase):
    def load(self, culture):
        lua = lupa.LuaRuntime()
        lua.execute(TABLE)
        lua.execute('''
CULTURE = "%s"
function StaticFindObject()
    return { GetCurrentCulture = function() return { ToString = function() return CULTURE end } end }
end
''' % culture)
        return lua.execute(TR.read_text(encoding="utf-8"))

    def test_english_is_unchanged(self):
        tr = self.load("en")
        s = "Deck 3, Turbo lift, decks 2 to 9, 5 of 10"
        self.assertEqual(tr.apply(s), s)
        self.assertEqual(tr.word("on"), "on")

    def test_german_phrases(self):
        tr = self.load("de-DE")
        self.assertEqual(tr.apply("Deck 3, Turbolift, decks 2 to 9, 5 of 10"),
                         "Deck 3, Turbolift, Decks 2 bis 9, 5 von 10")
        self.assertEqual(tr.apply("Ship view. Deck 5, Wissenschaftslabor."),
                         "Schiffsansicht. Deck 5, Wissenschaftslabor.")

    def test_longest_template_wins(self):
        tr = self.load("de")
        # "decks {n} to {n}" must win over "{n} to {n}".
        self.assertNotIn("BIS", tr.apply("decks 2 to 9"))
        self.assertIn("BIS", tr.apply("from 2 to 9"))

    def test_text_slot(self):
        tr = self.load("de")
        self.assertEqual(tr.apply("Not possible: Keine Lebenserhaltung"), "Nicht möglich: Keine Lebenserhaltung")

    def test_lone_word_only_by_exact_lookup(self):
        tr = self.load("fr")
        # The French game's own "on" (a pronoun) must survive the line pass.
        self.assertEqual(tr.apply("Salle, on peut entrer, 2 of 3"), "Salle, on peut entrer, 2 sur 3")
        self.assertEqual(tr.word("on"), "allumé")

    def test_long_lone_word_in_line_pass(self):
        tr = self.load("de")
        self.assertEqual(tr.apply("Tier 2, selected, 2 of 5"), "Tier 2, ausgewählt, 2 von 5")
        # Short lone words stay for the exact lookup.
        self.assertEqual(tr.apply("Mess Hall, on"), "Mess Hall, on")

    def test_reordered_slots(self):
        tr = self.load("de")
        self.assertEqual(tr.apply("12 cycles to analyze Borg Node now"), "jetzt Borg Node in 12 Zyklen analysieren")

    def test_translated_piece_is_not_translated_again(self):
        tr = self.load("de")
        # The translation still says "Press Enter:", which the general
        # template would take again without the marker.
        self.assertEqual(tr.apply("Press Enter: select"), "Press Enter: auswählen")
        # The general template still works on other text, and a piece
        # inside its slot is kept.
        self.assertEqual(tr.apply("Press Enter: Ship view"), "DOPPELT: Schiffsansicht")

    def test_trailing_slot_moves_with_its_sentence(self):
        tr = self.load("de")
        self.assertEqual(tr.apply("Not enough: Duranium, Tritanium. 3 of 4"), "Duranium, Tritanium fehlt. 3 von 4")

    def test_short_template_by_exact_fill(self):
        tr = self.load("de")
        # "{s} tab" is too short for the line pass ("Crew tab" stayed
        # English in the German tech tree, 2026-10-20), so it is filled
        # where it is made.
        self.assertEqual(tr.apply("Crew tab"), "Crew tab")
        self.assertEqual(tr.fill("{s} tab", "Crew"), "Registerkarte Crew")
        self.assertEqual(tr.fill("{s} needs {n}", "Labor", 3), "3 braucht Labor")
        # A % in the inserted text is kept as it is.
        self.assertEqual(tr.fill("{s} tab", "50%"), "Registerkarte 50%")

    def test_lowercase_template_at_sentence_start(self):
        tr = self.load("de")
        # events.lua capitalizes each part: "Up to 49 Tritanium" stayed
        # English in the German game (VM, 2026-10-20).
        self.assertEqual(tr.apply("Up to 49 Tritanium. Kein Risiko."), "Bis zu 49 Tritanium. Kein Risiko.")
        self.assertEqual(tr.apply("Option, up to 49 Tritanium"), "Option, bis zu 49 Tritanium")
        # A translation that starts with a slot keeps the slot as it is.
        self.assertEqual(tr.apply("To 3 done"), "3 fertig")

    def test_colon_word_in_line_pass(self):
        tr = self.load("de")
        self.assertEqual(tr.apply("Goal: Zerstöre den Gegner"), "Ziel: Zerstöre den Gegner")
        self.assertEqual(tr.apply("Verletzungen: none"), "Verletzungen: keine")

    def test_fill_in_english_and_unknown_template(self):
        tr = self.load("en")
        self.assertEqual(tr.fill("{s} tab", "Crew"), "Crew tab")
        tr = self.load("de")
        self.assertEqual(tr.fill("{s} room", "Crew"), "Crew room")

    def test_number_at_template_end_leaves_the_comma(self):
        # "26," was taken as the number, so ", base attack power 26" lost
        # its comma and stayed English (German Combat tab, VM, 2026-10-20).
        tr = self.load("de")
        self.assertEqual(tr.apply("Offensive combat power 26, base attack power 26"),
                         "Offensive Kampfkraft 26, Grundangriffskraft 26")
        # A thousands separator inside the number stays part of it.
        self.assertEqual(tr.apply("Offensive combat power 1,200."), "Offensive Kampfkraft 1,200.")

    def test_missing_table_is_english(self):
        tr = self.load("ja")
        self.assertEqual(tr.apply("5 of 10"), "5 of 10")
        self.assertEqual(tr.word("on"), "on")


if __name__ == "__main__":
    unittest.main()
