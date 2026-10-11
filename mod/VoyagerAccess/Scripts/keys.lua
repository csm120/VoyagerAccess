-- The mod's keys, read on the game thread. tools/speech_helper.py watches the
-- keyboard while the game is in front and appends one key name per line to
-- %LOCALAPPDATA%\VoyagerAccess\keys.txt ("enter", "shift+enter", "r", ...).
--
-- Not RegisterKeyBind: UE4SS runs those callbacks on its own thread, and its
-- game-thread loops run Lua without the lock, so a key press during a poll
-- corrupted the Lua heap (crash inside luaH_setint, 2026-10-10 22:24; the
-- source is LuaMod.cpp process_delayed_actions).

local crumb = require("crumb")

local M = {}

local PATH = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\keys.txt"
local INTERVAL_MS = 30

local handlers = {}
local pos = 0

-- os.time() of the last key Casey pressed in the game; devcmd refuses to
-- run probe commands while he is playing.
M.last_key_time = 0

-- fn runs on the game thread; errors are logged with the key name.
function M.on(name, fn)
    handlers[name] = fn
end

-- New complete lines since the last read, or nil.
local function read_new()
    local f = io.open(PATH, "rb")
    if not f then return nil end
    local size = f:seek("end")
    if size < pos then pos = 0 end      -- the helper restarted and emptied it
    if size == pos then
        f:close()
        return nil
    end
    f:seek("set", pos)
    local data = f:read("a")
    f:close()
    local cut = data:find("\n[^\n]*$")
    if not cut then return nil end
    pos = pos + cut
    return data:sub(1, cut)
end

local function dispatch()
    local data = read_new()
    if not data then return end
    M.last_key_time = os.time()
    require("speech").release()
    for name in data:gmatch("[^\r\n]+") do
        local fn = handlers[name]
        if fn then
            crumb.at("key: " .. name)
            local ok, err = pcall(fn)
            if not ok then print("[VoyagerAccess] " .. name .. " error: " .. tostring(err) .. "\n") end
        end
    end
end

function M.install()
    -- Keys pressed before the mod loaded are not replayed.
    local f = io.open(PATH, "rb")
    if f then
        pos = f:seek("end")
        f:close()
    end
    LoopInGameThreadWithDelay(INTERVAL_MS, function()
        local ok, err = pcall(dispatch)
        if not ok then print("[VoyagerAccess] keys error: " .. tostring(err) .. "\n") end
    end)
end

return M
