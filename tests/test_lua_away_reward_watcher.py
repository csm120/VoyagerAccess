"""awaymission.lua: a task's late reward watcher stops when the next result comes.

Fable review, 2026-11-10 (mod low 11): the 15 s reward watcher kept
looking under a result panel the next task reuses, so task 2's reward was
said twice (once by task 1's watcher). Runs the real awaymission.lua under
lupa, through mission_poll, with the stubs of test_lua_away_result_reset.
"""
import unittest

from tests.test_lua_away_result_arrows import SCRIPTS, STUBS, lupa
from tests.test_lua_away_result_reset import WINDOW

EXTRA = r"""
delayed = {}
function ExecuteInGameThreadWithDelay(ms, fn) delayed[#delayed + 1] = fn end
function run_delayed()
    for _ = 1, 40 do
        local d = delayed
        delayed = {}
        if #d == 0 then return end
        for _, fn in ipairs(d) do fn() end
    end
end
reward = ""
local function up(fn, name, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 255 do
        local n, v = debug.getupvalue(fn, i)
        if n == nil then break end
        if n == name then return fn, i end
        if type(v) == "function" then
            local a, b = up(v, name, seen)
            if a then return a, b end
        end
    end
end
function stub_rewards(M)
    local fn, i = up(M.mission_poll, "choice_rewards")
    debug.setupvalue(fn, i, function() return reward end)
end
"""


@unittest.skipIf(lupa is None, "lupa not installed")
class RewardWatcherTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.lua.execute(WINDOW)
        self.lua.execute(EXTRA)
        self.M = self.lua.execute("return (require('awaymission'))")
        self.M.mission_active = lambda: False
        self.lua.globals().stub_rewards(self.M)

    def rewards(self):
        return [s for s in self.lua.eval("said").values() if s.startswith("Reward:")]

    def test_reward_of_the_next_task_is_said_once(self):
        self.M.mission_poll()                   # task 1's result, no reward
        self.lua.execute("story = 'Tuvok finds the hidden cache.'; reward = '300 Food'")
        self.M.mission_poll()                   # task 2's result, reward comes late
        self.lua.execute("run_delayed()")
        self.assertEqual(len(self.rewards()), 1, self.rewards())

    def test_late_reward_is_said(self):
        # Negative twin: one task whose reward comes late is still told it.
        self.M.mission_poll()
        self.lua.execute("reward = '300 Food'")
        self.lua.execute("run_delayed()")
        self.assertEqual(self.rewards(), ["Reward: 300 Food"])


if __name__ == "__main__":
    unittest.main()
