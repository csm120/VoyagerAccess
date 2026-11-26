"""combat.lua: one failing part of the battle poll does not silence the rest.

Mode guards review, 2026-11-25 (section A, item 6 and the note on
combat.lua's energy hooks):
1. poll() called M.setup_sync() with no pcall, so an error there skipped
   every battle reader after it on that tick. It is now pcalled and the
   first failure logged.
2. energy_hooks() registers two hooks in one pcall. When the first was
   registered and the second failed with "no UFunction", the retry
   registered the first again, and each failed retry piled one more on.
Runs the real combat.lua under lupa with the stubs of test_lua_combat_pause.
"""
import unittest

from tests.test_lua_combat_pause import SCRIPTS, STUBS, lupa

EXTRA = r"""
printed = {}
print = function(s) printed[#printed + 1] = s end
registered = {}
fail_selected = FAIL_SELECTED
function RegisterHook(name, fn)
    registered[name] = (registered[name] or 0) + 1
    if fail_selected and name:find(":SetSelected", 1, true) then
        error("no UFunction found for SetSelected")
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
function find(M, name)
    for _, f in pairs(M) do
        if type(f) == "function" then
            local e = up(f, name)
            if e then return e end
        end
    end
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class CombatPollGuardTests(unittest.TestCase):
    def load(self, fail_selected=False):
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        lua.execute(STUBS)
        lua.globals().FAIL_SELECTED = fail_selected
        lua.execute(EXTRA)
        M = lua.execute("return (require('combat'))")
        return lua, M

    def run_poll(self, sync_fails):
        lua, M = self.load()
        calls = []

        def sync():
            calls.append("setup_sync")
            if sync_fails:
                raise RuntimeError("setup widget variant")

        def setup_up():
            calls.append("setup_up")
            return False

        M.setup_sync = sync
        M.setup_up = setup_up
        M.screen_up = lambda: False
        M.active = lambda: False
        poll = lua.globals().find(M, "poll")
        self.assertIsNotNone(poll)
        poll()
        return calls, list(lua.globals().printed.values())

    def test_setup_sync_error_still_runs_later_readers(self):
        calls, printed = self.run_poll(sync_fails=True)
        self.assertEqual(calls, ["setup_sync", "setup_up"])
        self.assertEqual(len([p for p in printed if "setup_sync failed" in p]), 1, printed)

    def test_setup_sync_working_is_unchanged(self):
        # Negative twin: no failure, the same readers run and nothing is logged.
        calls, printed = self.run_poll(sync_fails=False)
        self.assertEqual(calls, ["setup_sync", "setup_up"])
        self.assertEqual([p for p in printed if "setup_sync failed" in p], [])

    def energy_counts(self, fail_selected, tries=3):
        lua, M = self.load(fail_selected)
        energy_hooks = lua.globals().find(M, "energy_hooks")
        self.assertIsNotNone(energy_hooks)
        for _ in range(tries):
            energy_hooks()
        return {k.split(":")[-1]: v for k, v in lua.globals().registered.items()}

    def test_half_registered_energy_hooks_do_not_pile_up(self):
        c = self.energy_counts(fail_selected=True)
        self.assertEqual(c.get("OnEnergyChangedEvent"), 1, c)
        # The failing one is still tried again each time.
        self.assertEqual(c.get("SetSelected"), 3, c)

    def test_working_energy_hooks_register_once(self):
        # Negative twin: both register on the first try and never again.
        c = self.energy_counts(fail_selected=False)
        self.assertEqual(c.get("OnEnergyChangedEvent"), 1, c)
        self.assertEqual(c.get("SetSelected"), 1, c)


if __name__ == "__main__":
    unittest.main()
