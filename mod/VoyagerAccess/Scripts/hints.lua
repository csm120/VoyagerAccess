-- Key hints the mod adds to what it reads ("Left and Right choose another",
-- "Enter finishes it") are said the first two times only, counted across
-- sessions (Casey, 2026-10-19: "once you've been playing the game for a
-- couple of hours they get a bit frustrating. Again once or twice is fine").
-- F1 and Ctrl+F1 still list every key. Counts live in hints.txt beside
-- speech.txt, one "key=count" per line.

local M = {}

local LIMIT = 2
local counts = nil
local last = {}   -- key -> os.time() of the last count, so one reading
                  -- built several times in a moment counts once

local function file()
    return (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\hints.txt"
end

local function load()
    if counts then return end
    counts = {}
    local f = io.open(file(), "r")
    if not f then return end
    for line in f:lines() do
        local k, n = line:match("^([%w_]+)=(%d+)$")
        if k then counts[k] = tonumber(n) end
    end
    f:close()
end

local function save()
    local f = io.open(file(), "w")
    if not f then return end
    for k, n in pairs(counts) do f:write(k, "=", n, "\n") end
    f:close()
end

-- True while hint key may still be said; counts this use.
function M.fresh(key)
    local ok, yes = pcall(function()
        load()
        local n = counts[key] or 0
        if n >= LIMIT then return false end
        local now = os.time()
        if not (last[key] and now - last[key] < 10) then
            counts[key] = n + 1
            last[key] = now
            save()
        end
        return true
    end)
    return not ok or yes
end

-- text when the hint is still fresh, else "".
function M.text(key, text)
    return M.fresh(key) and text or ""
end

return M
