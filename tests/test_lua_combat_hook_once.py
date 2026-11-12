"""combat.lua: the combat window's hooks are registered once per session.

Fable review, 2026-11-10 (mod finding 2): when OnCombatPauseChanged would
not hook (a patch renames it), ensure_pause_hook ran again on every 500 ms
poll and registered the target, hit and status hooks again each time, so
one Tab said "Target: ..." once per poll that had passed. Runs the real
combat.lua under lupa with the stubs of test_lua_combat_pause.
"""
import unittest

from tests.test_lua_combat_pause import SCRIPTS, STUBS, lupa

COUNTING = r"""
registered = {}
local fail_pause = FAIL_PAUSE
function RegisterHook(name, fn)
    registered[name] = (registered[name] or 0) + 1
    if fail_pause and name:find(":OnCombatPauseChanged", 1, true) then
        error("no such function")
    end
    hooks[name] = fn
    return 1, 2
end
local function up(fn, name, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 255 do
        local n, v = debug.getupvalue(fn, i)
        if n == nil then break end
        if n == name then return v end
        if type(v) == "function" then
            local a = up(v, name, seen)
            if a then return a end
        end
    end
end
function find_ensure(M)
    for _, f in pairs(M) do
        if type(f) == "function" then
            local e = up(f, "ensure_pause_hook")
            if e then return e end
        end
    end
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class HookOnceTests(unittest.TestCase):
    def counts(self, fail_pause, polls=5):
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        lua.execute(STUBS)
        lua.globals().FAIL_PAUSE = fail_pause
        lua.execute(COUNTING)
        M = lua.execute("return (require('combat'))")
        M.active = lambda: True
        M.paused_text = lambda w: None
        g = lua.globals()
        g.setup(M)                   # the first poll
        ensure = g.find_ensure(M)
        for _ in range(polls - 1):
            ensure()
        return {k.split(":")[-1]: v for k, v in g.registered.items()}

    def test_failed_pause_hook_does_not_pile_up_the_others(self):
        c = self.counts(fail_pause=True)
        self.assertEqual(c.get("OnSwitchedToEnemy"), 1, c)
        self.assertEqual(c.get("PlayerDamaged"), 1, c)
        self.assertEqual(c.get("OnCombatantStatusChangeBP"), 1, c)

    def test_working_hooks_are_registered_once(self):
        # Negative twin: the normal case already registered each once.
        c = self.counts(fail_pause=False)
        self.assertEqual(c.get("OnCombatPauseChanged"), 1, c)
        self.assertEqual(c.get("OnSwitchedToEnemy"), 1, c)


if __name__ == "__main__":
    unittest.main()
