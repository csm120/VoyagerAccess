"""whatsnew.lua: Ctrl+F12's release notes stay wholly English.

Fable review, 2026-11-10 (mod low 20), Casey's answer the same day: the
English notes went through the translation line pass, which swapped
fragments ("Fixed: when the game ignored Eingabe on a choice"). The items
now skip it; the mod's own "Closed" is still translated. Runs the real
whatsnew.lua and speech.lua under lupa, with a German-like tr stub.
"""
import unittest

from tests.test_lua_repeat_result import SCRIPTS, lupa

STUBS = r"""
written = {}
print = function() end
package.preload["tr"] = function()
    local function de(s) return (s:gsub("Enter", "Eingabe"):gsub("Closed", "Geschlossen")) end
    return { apply = de, line = de, word = de, fill = function(s) return s end }
end
package.preload["language"] = function() return { english = function() return false end } end
package.preload["focus"] = function() return { park_focus = function() end } end
package.preload["keys"] = function() return { on = function() end } end
io.open = function(p, m)
    return { write = function(self, ...) for _, s in ipairs({...}) do written[#written + 1] = s end return self end,
             close = function() end, flush = function() end, seek = function() return 0 end,
             read = function() return nil end, lines = function() return function() return nil end end }
end
function stub_items(M, list)
    for i = 1, 255 do
        local n = debug.getupvalue(M.toggle, i)
        if n == nil then break end
        if n == "load_items" then debug.setupvalue(M.toggle, i, function() return list end) end
    end
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class WhatsNewEnglishTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('whatsnew'))")
        items = self.lua.table("Version 0.4.2. Fixed: when the game ignored Enter on a choice, it is clicked again.")
        self.lua.globals().stub_items(self.M, items)

    def written(self):
        return "".join(self.lua.globals().written.values())

    def test_release_note_stays_english(self):
        self.M.toggle()
        self.assertIn("ignored Enter on a choice", self.written())
        self.assertNotIn("Eingabe", self.written())

    def test_closed_is_still_translated(self):
        # Negative twin: the mod's own word is still in the game's language.
        self.M.toggle()
        self.M.close()
        self.assertIn("Geschlossen", self.written())


if __name__ == "__main__":
    unittest.main()
