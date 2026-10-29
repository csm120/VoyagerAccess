-- Starts the speech helper when none is running (Casey, 2026-10-29: "the
-- mod should start the helper whenever possible"). Normally Steam starts
-- the helper, which starts the game; when the launch option is missing or
-- was reset, the helper never runs and the mod has no voice at all.
--
-- The helper writes the time (seconds, os.time's scale) to
-- helper-alive.txt about every second while it serves. keys.lua calls
-- check() every 2 s; once the mod has been up GRACE seconds, a missing or
-- stale file starts the installed helper with --attach, at most TRIES
-- times, a minute apart, through io.popen (UE4SS Lua has it; checked in the VM,
-- 2026-10-29).

local M = {}

local DIR = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\"
local ALIVE = DIR .. "helper-alive.txt"
local EXE = (os.getenv("LOCALAPPDATA") or ".") .. "\\Programs\\VoyagerAccess\\VoyagerAccess.exe"
local GRACE, STALE, GAP, TRIES = 15, 10, 60, 3

local loaded_at = nil
local last_try = nil
local tries = 0

function M.loaded()
    loaded_at = os.time()
end

local function helper_alive(now)
    local f = io.open(ALIVE, "r")
    if not f then return false end
    local t = tonumber(f:read("a") or "")
    f:close()
    return t ~= nil and now - t < STALE
end

local function installed()
    local f = io.open(EXE, "rb")
    if f then f:close() end
    return f ~= nil
end

local pending, pending_at = nil, 0
local CLOSE_AFTER = 20

-- voystart.dll's voy_start, or nil. The DLL sits in the mod's folder, one
-- up from this file ("@D:/.../Mods/VoyagerAccess/Scripts/helperstart.lua",
-- VM, 2026-10-29).
local native, native_tried = nil, false
local function native_start()
    if native_tried then return native end
    native_tried = true
    pcall(function()
        local src = debug.getinfo(1, "S").source:gsub("^@", "")
        local dir = src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]+$")
        if dir then native = package.loadlib(dir .. "/voystart.dll", "voy_start") end
    end)
    return native
end

function M.check()
    local now = os.time()
    if pending and now - pending_at >= CLOSE_AFTER then
        pcall(function() pending:close() end)
        pending = nil
    end
    if not loaded_at or now - loaded_at < GRACE then return end
    if tries >= TRIES or (last_try and now - last_try < GAP) then return end
    if helper_alive(now) then return end
    if not installed() then return end
    last_try = now
    tries = tries + 1
    -- First voystart.dll (installer\native\voystart.c), next to Scripts:
    -- CreateProcess with no window at all. Casey asked for no command line
    -- windows (2026-10-29); through cmd.exe, NVDA said "cmd.exe".
    local start = native_start()
    if start then
        print("[VoyagerAccess] no speech helper running; starting it (try " .. tries .. ", voystart.dll)\n")
        pcall(start)
        return
    end
    print("[VoyagerAccess] no speech helper running; starting it (try " .. tries .. ", io.popen)\n")
    local cmd = 'start "" "' .. EXE .. '" --attach'
    -- Without the DLL, io.popen, not os.execute: os.execute's console window
    -- took focus and NVDA said "Terminal ... cmd.exe"; io.popen's did not
    -- take focus, though NVDA still said "cmd.exe" once (VM, 2026-10-29).
    -- Opened for writing and closed on a later check: closing at once held
    -- the game thread 5 to 6 s while cmd.exe exited; 15 s later the close
    -- took 0.25 ms (opening, 7 ms).
    local ok, p = pcall(io.popen, cmd, "w")
    if ok and p then
        pending, pending_at = p, now
    else
        pcall(os.execute, cmd)
    end
end

return M
