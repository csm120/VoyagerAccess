-- Crash breadcrumbs: UE4SS dies with an access violation that Lua cannot
-- catch, and UE4SS.log loses its last lines when the game dies. So each
-- risky step overwrites one small file, flushed by closing it, and after a
-- crash that file names the last step that started. Development only.

local M = {}

local PATH = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\crumb.txt"

-- With the timing log on (timing.lua), each step's start is also kept, so
-- a slow callback can say which step took the time.
M.steps = nil   -- { {step, os.clock()}, ... } while timing.lua collects

-- The file is written only with the flag file "crumb": each write held the
-- game 1 to 9 ms, several times on every key, for every player (measured
-- 2026-10-25, Mess Hall: up to 14 ms of a 34 ms look).
local WRITE = (function()
    local f = io.open((os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\crumb", "r")
    if f then f:close() return true end
    return false
end)()

function M.at(step)
    if WRITE then
        -- Development measurement (flag file "steps", timing.lua): the file
        -- write's own cost is timed as a step of its own, before the step.
        if M.steps and M.time_writes then M.steps[#M.steps + 1] = { "crumb write", os.clock(), collectgarbage("count") } end
        local f = io.open(PATH, "w")
        if f then
            f:write(os.date("%H:%M:%S "), step)
            f:close()
        end
    end
    if M.steps then M.steps[#M.steps + 1] = { step, os.clock(), collectgarbage("count") } end
end

return M
