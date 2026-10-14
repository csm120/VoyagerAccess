-- Credits (main menu): the game scrolls one rich text block of 420 lines
-- past the screen, and the mod said nothing while the arrows moved the main
-- menu hidden behind it (2026-10-14, VM run). While the credits are up they
-- are a list: each heading with its names is one item. Up and Down move,
-- Home and End go to the ends, Escape (the game's own) closes them.

local speech = require("speech")

local M = {}

local items, index, shown_path = nil, nil, nil

local function credits_widget()
    for _, w in ipairs(FindAllOf("WBP_Credits_C") or {}) do
        if w:IsValid() and w:GetFullName():find("/Engine/Transient.", 1, true) and w:IsInViewport() then
            return w
        end
    end
    return nil
end

-- "<H2>Writing</>\nA\nB\n\n<H2>..." -> { "Writing: A, B", ... }
local function parse(text)
    local list, heading, names = {}, nil, {}
    local function flush()
        if heading or #names > 0 then
            local item = heading or ""
            if #names > 0 then item = (heading and (heading .. ": ") or "") .. table.concat(names, ", ") end
            list[#list + 1] = item
        end
        heading, names = nil, {}
    end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local tagged = line:match("^%s*<[^>]+>(.-)</>%s*$")
        local plain = line:gsub("<[^>]*>", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if tagged then
            flush()
            heading = tagged:gsub("^%s+", ""):gsub("%s+$", "")
        elseif plain == "" then
            flush()
        else
            names[#names + 1] = plain
        end
    end
    flush()
    return list
end

local function say_item(interrupt)
    speech.say(string.format("%s, %d of %d", items[index], index, #items), interrupt)
end

function M.open()
    return items ~= nil
end

function M.step(dir)
    if items[index + dir] then index = index + dir end
    say_item(true)
end

function M.edge(last)
    index = last and #items or 1
    say_item(true)
end

function M.repeat_item()
    say_item(true)
end

local function poll()
    local w = credits_widget()
    if not w then
        if items then items, index, shown_path = nil, nil, nil end
        return
    end
    local path = w:GetFullName()
    if items and shown_path == path then return end
    local text = nil
    for _, t in ipairs(FindAllOf("RichTextBlock") or {}) do
        if t:IsValid() and t:GetFullName():find("WBP_Credits_C_", 1, true) then
            text = t:GetText():ToString()
        end
    end
    if not text then return end
    local list = parse(text)
    if #list == 0 then return end
    items, index, shown_path = list, 1, path
    require("focus").park_focus()
    print(string.format("[VoyagerAccess] credits: %d items\n", #list))
    speech.say(string.format("Credits, %d entries. Up and Down to read, Escape to close.", #list), true)
    say_item(false)
end

M.parse = parse

function M.install()
    LoopInGameThreadWithDelay(300, function()
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] credits error: " .. tostring(err) .. "\n") end
    end)
end

return M
