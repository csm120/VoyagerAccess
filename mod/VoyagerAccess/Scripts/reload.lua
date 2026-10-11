-- Reloads the mod when the helper asks: after an update it copies new
-- scripts into this folder and creates %LOCALAPPDATA%\VoyagerAccess\reload.
-- RestartCurrentMod from a game-thread loop ran safely many times as the
-- development RELOAD command (2026-10-10 and 10-11).

local FLAG = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\reload"

return function()
    LoopInGameThreadWithDelay(1000, function()
        local f = io.open(FLAG, "r")
        if not f then return end
        f:close()
        os.remove(FLAG)
        print("[VoyagerAccess] reloading for an update\n")
        RestartCurrentMod()
    end)
end
