-- Crash breadcrumbs: UE4SS dies with an access violation that Lua cannot
-- catch, and UE4SS.log loses its last lines when the game dies. So each
-- risky step overwrites one small file, flushed by closing it, and after a
-- crash that file names the last step that started. Development only.

local M = {}

local PATH = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\crumb.txt"

function M.at(step)
    local f = io.open(PATH, "w")
    if not f then return end
    f:write(os.date("%H:%M:%S "), step)
    f:close()
end

return M
