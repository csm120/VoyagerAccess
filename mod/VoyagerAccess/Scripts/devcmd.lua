-- Development back door: runs Lua dropped into
-- %LOCALAPPDATA%\VoyagerAccess\command.lua on the game thread, then deletes
-- the file. print() output goes to UE4SS.log. Lets the live game be inspected
-- without restarting it or asking Casey to press keys. Local file only.

local PATH = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\command.lua"

local function run()
    local f = io.open(PATH, "r")
    if not f then return end
    local code = f:read("a")
    f:close()
    os.remove(PATH)
    -- Probe commands crashed the game three times on 2026-10-10 while Casey
    -- was playing (GetText on every object; a missing-object lookup;
    -- GetPropertyClass on a text parameter). Pcall cannot catch those. So
    -- no command runs within 10 seconds of a key press in the game (five
    -- minutes at first; Casey asked for it shorter).
    -- A plain reload of the mod is allowed: it ran safely many times that day.
    -- Except with a window or one of the mod's lists open: that stopped the
    -- mod's Lua with a room window (three times), the Construction Report,
    -- and the credits list on Casey's machine (2026-10-14). The check lives
    -- here so every reload path meets it; "RELOAD FORCE" skips it.
    if code:match("^%s*RELOAD%s*$") then
        local why = nil
        pcall(function()
            for _, p in ipairs(require("popups").open_windows()) do
                if not p:find("WBP_PoiEventWidget_C", 1, true) and not p:find("RoomPrompt", 1, true) then why = p:match("([%w_]+)$") end
            end
            if require("credits").open() then why = "credits list" end
            if require("ship").list_open() then why = "room list" end
            if require("resources").list_open() then why = "resources list" end
            if require("view").nav_open() then why = "navigation list" end
            if require("whatsnew").open() then why = "what's new list" end
            if require("hotkeys").open() then why = "key list" end
        end)
        if why then
            print("[VoyagerAccess] cmd reload refused: " .. why .. " is open\n")
            return
        end
    end
    if code:match("^%s*RELOAD%s*$") or code:match("^%s*RELOAD FORCE%s*$") then
        print("[VoyagerAccess] cmd reload\n")
        RestartCurrentMod()
        return
    end
    local idle = os.time() - require("keys").last_key_time
    if idle < 10 then
        print("[VoyagerAccess] cmd refused: Casey pressed a key " .. idle .. " s ago\n")
        return
    end
    -- Never ForEachUObject calling methods on every object: asking every
    -- object for GetText crashed the game (2026-10-10 22:46).
    require("crumb").at("devcmd: running command")
    -- StaticFindObject and FindFirstOf return an invalid object, not nil,
    -- when nothing matches, and using it crashes the game; that crashed it
    -- from a command on 2026-10-10 23:18 (the second command crash that
    -- day). Commands get versions that return nil instead.
    local env = setmetatable({}, { __index = _G })
    local function guarded(fn)
        return function(...)
            local o = fn(...)
            if o == nil or not o:IsValid() then return nil end
            return o
        end
    end
    env.StaticFindObject = guarded(StaticFindObject)
    env.FindFirstOf = guarded(FindFirstOf)
    local chunk, err = load(code, "command", "t", env)
    if not chunk then
        print("[VoyagerAccess] cmd compile error: " .. tostring(err) .. "\n")
        return
    end
    local ok, result = pcall(chunk)
    print("[VoyagerAccess] cmd " .. (ok and "ok: " or "error: ") .. tostring(result) .. "\n")
end

-- Runs on the game thread directly; LoopAsync plus ExecuteInGameThread is a
-- suspect in an idle crash inside UE4SS (2026-10-10 20:28, not proven).
-- Only on a development machine: released copies must not run whatever Lua
-- lands in a file. The flag is %LOCALAPPDATA%\VoyagerAccess\dev (any
-- contents); the installer never creates it.
local FLAG = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\dev"

return function()
    local f = io.open(FLAG, "r")
    if not f then return end
    f:close()
    print("[VoyagerAccess] development commands enabled\n")
    pcall(function() require("unread").install() end)
    LoopInGameThreadWithDelay(500, function()
        local ok, err = pcall(run)
        if not ok then print("[VoyagerAccess] cmd loop error: " .. tostring(err) .. "\n") end
    end)
end
