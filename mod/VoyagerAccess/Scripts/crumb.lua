-- Crash breadcrumbs: UE4SS dies with an access violation that Lua cannot
-- catch, and UE4SS.log loses its last lines when the game dies. So each
-- risky step overwrites one small file, flushed by closing it, and after a
-- crash that file names the last step that started. Development only.

local M = {}

local PATH = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\crumb.txt"

-- With the timing log on (timing.lua), each step's start is also kept, so
-- a slow callback can say which step took the time.
M.steps = nil   -- { {step, os.clock()}, ... } while timing.lua collects

function M.at(step)
    if M.steps then M.steps[#M.steps + 1] = { step, os.clock() } end
    local f = io.open(PATH, "w")
    if not f then return end
    f:write(os.date("%H:%M:%S "), step)
    f:close()
end

return M
