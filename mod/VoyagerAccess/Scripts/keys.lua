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
-- Keys read so far, for code that must notice a key arriving while it
-- works (events.lua's chance sweep).
M.key_count = 0

local TUTORIAL_KEYS = { up = true, down = true, left = true, right = true, home = true, ["end"] = true }

-- fn runs on the game thread; errors are logged with the key name.
function M.on(name, fn)
    handlers[name] = fn
end

-- Functions told after every batch of input, the game's own keys and mouse
-- buttons too: anything the player presses can move the game's focus, so
-- focus.lua looks once after each instead of every 100 ms (firefly82,
-- 2026-10-21: the mod's loops held the game long enough to swallow keys).
local listeners = {}
function M.on_any(fn)
    listeners[#listeners + 1] = fn
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
    local released = false
    local input = false
    for name in data:gmatch("[^\r\n]+") do
        -- The helper's notes about itself ("helper: speech took 40 ms") are
        -- no key: counting them kept every development command refused
        -- (2026-10-21). Nor are commands from the helper or the development
        -- tools ("cmd:reload", "cmd:run"), which use this channel instead of
        -- flag files looked for on a timer.
        local command = name:find("^cmd:") ~= nil
        if not name:match("^log:%S+ helper: ") and not command then
            M.last_key_time = os.time()
            input = true
        end
        -- Every key and mouse button the player used while the game was in
        -- front, the game's own keys too ("E down", "E up after 80 ms"),
        -- from the helper's input log: written to UE4SS.log only, so the log
        -- shows what the player did between the game's lines (firefly82,
        -- 2026-10-21; an E that did nothing could not be told from one never
        -- pressed). Nothing acts on them.
        local logged = name:match("^log:(.*)$")
        -- "seen": a key or mouse button in the game with the input log off;
        -- it only counts as input for the listeners (focus looks then).
        -- "press": the player pressed one the mod does not handle (sent
        -- with "seen"; a release or the mod's own click is only "seen").
        if logged or name == "seen" or name == "press" then
            if logged then print("[VoyagerAccess] input " .. logged .. "\n") end
            -- A game key (Tab, E, a mouse button) is the player moving on
            -- too: what the mod said by itself no longer holds the next
            -- line back (speech.lua; GPT review, 2026-10-26). Only a press
            -- by the player of a key the mod does not handle: a release
            -- ended the hold of the room window Enter had just opened, so
            -- its focused button cut the window off (Casey's log, 09:23,
            -- 2026-10-26). The helper sends "press" for such presses;
            -- logged lines are told apart here (a 0.5 s window after the
            -- mod's key missed a long-held Enter's release and also ignored
            -- an E pressed 0.3 s after; GPT review of that fix).
            local press = name == "press" or (logged and not logged:find("^%S+ helper: ")
                and not logged:find(" up after ", 1, true) and not logged:find("(mod key:", 1, true)
                and not logged:find("by the mod", 1, true)
                -- Nor a screen reader's command (Insert or Caps Lock, alone
                -- or held): NVDA+Up to hear a line again ended the hold on
                -- what was being read (Fable review, 2026-10-26). The helper's
                -- player_press has the same rule.
                and not logged:find(" Insert down", 1, true) and not logged:find(" Caps Lock down", 1, true)
                and not (logged:match(" down with ([^%[(]*)") or ""):find("Insert", 1, true)
                and not (logged:match(" down with ([^%[(]*)") or ""):find("Caps Lock", 1, true))
            if press and not released then
                require("speech").release()
                released = true
            end
        else
            if not released and not command then
                require("speech").release()
                released = true
            end
            -- Every key in UE4SS.log too, so a player's report shows what was
            -- pressed before something went wrong (the crumb keeps only the
            -- last one; outside review, 2026-10-17).
            print("[VoyagerAccess] key: " .. name .. "\n")
            -- Real keys only: a "cmd:" line counted here stopped the event
            -- chance sweep as if the player had pressed a key (merge with
            -- firefly82's patch, 2026-10-21).
            if not command then M.key_count = M.key_count + 1 end
            local fn = handlers[name]
            -- A tutorial stays open until Enter now (Casey, 2026-10-23):
            -- the moving keys say so instead of acting behind it.
            if fn and TUTORIAL_KEYS[name] then
                local okt, up = pcall(function() return require("popups").tutorial_open() end)
                if okt and up then
                    fn = nil
                    pcall(function() require("speech").say("Tutorial open. Enter closes it, R repeats it.", true) end)
                end
            end
            -- A loading screen: the moving keys, Enter and I say so and how
            -- far it is, since nothing else answers them then (player
            -- report, 2026-10-24: "game seemed to stall"). The key still
            -- reaches its handler, in case the screen is only fading out;
            -- I would say just "Game." over it, so it does not.
            if TUTORIAL_KEYS[name] or name == "enter" or name == "i" then
                local okl, step = pcall(function() return require("popups").loading_step() end)
                if okl and step then
                    local line = step ~= "" and ("Loading. " .. step) or "Loading, please wait."
                    print("[VoyagerAccess] loading: " .. line .. "\n")
                    pcall(function() require("speech").say(line, true) end)
                    pcall(function() require("popups").loading_said_at = os.clock() end)
                    if name == "i" then fn = nil end
                end
            end
            if fn then
                crumb.at("key: " .. name)
                local ok, err = pcall(fn)
                if not ok then print("[VoyagerAccess] " .. name .. " error: " .. tostring(err) .. "\n") end
            end
        end
    end
    if input then
        for _, fn in ipairs(listeners) do
            local ok, err = pcall(fn)
            if not ok then print("[VoyagerAccess] input listener error: " .. tostring(err) .. "\n") end
        end
    end
end

-- Ctrl+F11: the helper switches its input log on or off and keeps the
-- choice in a file; it is off until switched on (firefly82's log, 2026-10-21;
-- off by default because UE4SS.log goes into public bug reports). The mod
-- says which.
local LOG_ON = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\input-log-on"
local function say_log_state()
    local f = io.open(LOG_ON, "r")
    if f then f:close() end
    require("speech").say(f and "Input log on" or "Input log off", true)
end

-- The helper's sign that the mod and the game are alive (helper.py
-- HeartbeatWatch): this loop touches heartbeat.txt about every 2 s, so a
-- hung game or a dead keys loop is said instead of going silent (the WFH
-- session's reliability review, 2026-10-29). One small write per 2 s, on
-- the loop that already runs; no loop of its own.
local HEARTBEAT = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\heartbeat.txt"
local last_beat = 0
local function heartbeat()
    local now = os.time()
    if now - last_beat < 2 then return end
    last_beat = now
    local f = io.open(HEARTBEAT, "w")
    if f then
        f:write(tostring(now))
        f:close()
    end
    -- The other direction: no helper running, so start one (helperstart.lua).
    local ok, err = pcall(function() require("helperstart").check() end)
    if not ok then print("[VoyagerAccess] helperstart error: " .. tostring(err) .. "\n") end
end

function M.install()
    M.on("ctrl+f11", say_log_state)
    pcall(function() require("helperstart").loaded() end)
    -- Keys pressed before the mod loaded are not replayed.
    local f = io.open(PATH, "rb")
    if f then
        pos = f:seek("end")
        f:close()
    end
    LoopInGameThreadWithDelay(INTERVAL_MS, function()
        local ok, err = pcall(dispatch)
        if not ok then print("[VoyagerAccess] keys error: " .. tostring(err) .. "\n") end
        heartbeat()
    end)
end

return M
