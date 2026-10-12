-- Ctrl+F12: What's new, as a list (Casey, 2026-10-11, "like how we did for
-- status with C"). It reads whats_new.md, a copy of docs\WHATS_NEW.md that
-- the build puts in the mod folder, so the game and the public page say
-- the same thing. Each bullet is one item, newest release first; the first
-- item of each release starts with its version. Up and Down move, Home and
-- End go to the ends, Ctrl+F12 again, Backspace or Enter close it.

local speech = require("speech")

local M = {}

local function mod_dir()
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    return src:match("^(.*)[/\\]Scripts[/\\][^/\\]+$")
end

local function load_items()
    local dir = mod_dir()
    local f = dir and io.open(dir .. "\\whats_new.md", "r")
    if not f then return nil end
    local items, version, first = {}, nil, false
    for line in f:lines() do
        local v = line:match("^Version (%S+)")
        if v then
            version, first = v, true
        elseif version and line:match("%S") and not line:match("^#") then
            -- Everything in this list is new, so "New:" is left off; "Fixed:"
            -- and "Changed:" stay, since they say something (Casey, 2026-10-11).
            local text = line:gsub("^%- ", ""):gsub("%*", ""):gsub("^New: ", "")
            text = text:sub(1, 1):upper() .. text:sub(2)
            if first then
                text = "Version " .. version .. ". " .. text
                first = false
            end
            items[#items + 1] = text
        end
    end
    f:close()
    return items
end

local items, index = nil, nil

local function say_item()
    speech.say(string.format("%s %d of %d", (items[index]:gsub("%.?%s*$", ".")), index, #items), true)
end

function M.open()
    return items ~= nil
end

function M.toggle()
    if items then
        items = nil
        speech.say("Closed", true)
        return
    end
    local list = load_items()
    if not list or #list == 0 then
        speech.say("What's new is not available", true)
        return
    end
    items, index = list, 1
    require("focus").park_focus()
    say_item()
end

function M.step(dir)
    if items[index + dir] then index = index + dir end
    say_item()
end

function M.edge(last)
    index = last and #items or 1
    say_item()
end

function M.close()
    if not items then return false end
    items = nil
    speech.say("Closed", true)
    return true
end

function M.install()
    require("keys").on("ctrl+f12", M.toggle)
end

return M
