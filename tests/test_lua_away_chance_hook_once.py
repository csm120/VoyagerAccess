"""awaymission.lua: OnNoHeroesSelected is hooked once, whatever the chance hook does.

Fable review, 2026-11-10 (mod low 13): when the chance hook would not go
in and the OnNoHeroesSelected one did, every call to ensure_chance_hook
(each task label read) added another OnNoHeroesSelected hook. Runs the
real awaymission.lua under lupa with the stubs of
test_lua_away_result_arrows.
"""
import unittest

from tests.test_lua_away_result_arrows import SCRIPTS, STUBS, lupa

COUNTING = r"""
counts = {}
fail_chance = true
function StaticFindObject() return { IsValid = function() return true end } end
function RegisterHook(name, fn)
    local key = name:match(":(%w+)$")
    counts[key] = (counts[key] or 0) + 1
    if fail_chance and key ~= "OnNoHeroesSelected" then error("not found") end
    return 1, 2
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class ChanceHookOnceTests(unittest.TestCase):
    def run_hooks(self, fail_chance):
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        lua.execute(STUBS)
        lua.execute(COUNTING)
        lua.globals().fail_chance = fail_chance
        M = lua.execute("return (require('awaymission'))")
        for _ in range(4):
            M.ensure_chance_hook()
        return dict(lua.globals().counts.items())

    def test_no_heroes_hook_does_not_pile_up(self):
        self.assertEqual(self.run_hooks(True).get("OnNoHeroesSelected"), 1)

    def test_both_hooks_in_once(self):
        # Negative twin: the normal case registers each once.
        c = self.run_hooks(False)
        self.assertEqual(c.get("OnNoHeroesSelected"), 1)
        self.assertEqual(sum(c.values()), 2, c)


if __name__ == "__main__":
    unittest.main()
