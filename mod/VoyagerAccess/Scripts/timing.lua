-- Development only (the "timing" flag file in %LOCALAPPDATA%\VoyagerAccess):
-- how long each piece of the mod's own work held the game. After the loops
-- were replaced by the game's events, keys still reached the mod 300 to
-- 430 ms late, a sign that the game thread was held (firefly82's test,
-- 2026-10-21), and the code alone does not say by what. Every callback the
-- mod hands to UE4SS (loops, delayed and next-tick calls, hooks, new-object
-- notifications) is wrapped once here, before any module installs: one
-- that takes 20 ms or more is logged with where it was defined, and so is a
-- Lua garbage collection that ran inside it (memory went down).
local M = {}

local LIMIT = 0.020   -- seconds; a frame at 50 frames a second

local function where(fn)
    local ok, info = pcall(debug.getinfo, fn, "S")
    if not ok or not info then return "?" end
    -- A development command's chunk has no file name ("command").
    local src = tostring(info.short_src or "?")
    return (src:match("([%w_]+%.lua)") or src) .. ":" .. tostring(info.linedefined)
end

local function timed(kind, fn)
    if type(fn) ~= "function" then return fn end
    local name = kind .. " " .. where(fn)
    return function(...)
        local mem0 = collectgarbage("count")
        local crumb = require("crumb")
        local outer = crumb.steps
        crumb.steps = {}
        local t0 = os.clock()
        local r = table.pack(pcall(fn, ...))
        local dt = os.clock() - t0
        local mem1 = collectgarbage("count")
        local steps = crumb.steps
        crumb.steps = outer
        if dt >= LIMIT or mem1 < mem0 then
            -- The step (crumb.at) that took longest, from its start to the
            -- next step or the end.
            local slow = ""
            if dt >= LIMIT and #steps > 0 then
                local worst, worst_dt = "start", steps[1][2] - t0
                for i, s in ipairs(steps) do
                    local stop = steps[i + 1] and steps[i + 1][2] or (t0 + dt)
                    if stop - s[2] > worst_dt then worst, worst_dt = s[1], stop - s[2] end
                end
                slow = string.format(", slowest step %d ms: %s", math.floor(worst_dt * 1000 + 0.5), tostring(worst):sub(1, 80))
            end
            print(string.format("[VoyagerAccess] timing: %s took %d ms%s%s\n", name, math.floor(dt * 1000 + 0.5),
                mem1 < mem0 and string.format(", Lua memory %d to %d KB (collected)", math.floor(mem0), math.floor(mem1)) or "", slow))
        end
        -- Development measurement (flag file "steps", 2026-10-25): every
        -- callback with steps, each step with its time and the Lua memory
        -- it made, whatever the total.
        if M.all_steps and #steps > 1 then
            local parts = {}
            for i, s in ipairs(steps) do
                local stop = steps[i + 1] and steps[i + 1][2] or (t0 + dt)
                local mstop = steps[i + 1] and steps[i + 1][3] or mem1
                parts[#parts + 1] = string.format("%s %.1f ms %+d KB", tostring(s[1]):sub(1, 40), (stop - s[2]) * 1000, math.floor(mstop - (s[3] or mstop)))
            end
            print(string.format("[VoyagerAccess] steps: %s %.1f ms %+d KB: %s\n", name, dt * 1000, math.floor(mem1 - mem0), table.concat(parts, " | ")))
        end
        if not r[1] then error(r[2], 0) end
        return table.unpack(r, 2, r.n)
    end
end

function M.install()
    if TIMING_WRAPPED then return end
    TIMING_WRAPPED = true
    local loop, later, now, hook, notify = LoopInGameThreadWithDelay, ExecuteInGameThreadWithDelay,
        ExecuteInGameThread, RegisterHook, NotifyOnNewObject
    LoopInGameThreadWithDelay = function(ms, fn) return loop(ms, timed("loop", fn)) end
    ExecuteInGameThreadWithDelay = function(ms, fn) return later(ms, timed("delayed", fn)) end
    ExecuteInGameThread = function(fn) return now(timed("next tick", fn)) end
    RegisterHook = function(path, pre, post)
        local short = tostring(path):match("([^%.:/]+:[%w_]+)$") or tostring(path)
        -- No explicit nil for a missing post callback: a UE4SS build that
        -- refused one would fail every hook while timing is on.
        if not post then return hook(path, timed("hook " .. short, pre)) end
        return hook(path, timed("hook " .. short, pre), timed("hook post " .. short, post))
    end
    NotifyOnNewObject = function(cls, fn) return notify(cls, timed("new object", fn)) end
    local f = io.open((os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\steps", "r")
    if f then
        f:close()
        M.all_steps = true
        require("crumb").time_writes = true
        print("[VoyagerAccess] timing: every step of every callback logged (steps)\n")
    end
    print("[VoyagerAccess] timing: on, logging mod work of 20 ms or more and Lua collections\n")
end

return M
