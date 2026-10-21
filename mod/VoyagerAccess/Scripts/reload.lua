-- Reloads the mod when the helper asks: after an update it copies new
-- scripts into this folder and writes "cmd:reload" into keys.txt, the
-- channel the mod reads anyway (keys.lua). It used to create a flag file
-- that the mod looked for every second; the mod's loops held the game long
-- enough to swallow keys (firefly82, 2026-10-21).
-- RestartCurrentMod from the game thread ran safely many times as the
-- development RELOAD command (2026-10-10 and 10-11).

return function()
    require("keys").on("cmd:reload", function()
        print("[VoyagerAccess] reloading for an update\n")
        RestartCurrentMod()
    end)
end
