-- Credits (main menu): the game scrolls one rich text block of 420 lines
-- past the screen, and the mod said nothing while the arrows moved the main
-- menu hidden behind it (2026-10-14, VM run). While the credits are up they
-- are a list: each heading with its names is one item. Up and Down move,
-- Home and End go to the ends, Escape (the game's own) closes them.

local speech = require("speech")

local M = {}

local items, index, shown_path = nil, nil, nil

-- The credits widget the game has activated (its own BP_OnActivated and
-- BP_OnDeactivated, WBP_Credits_C in the CXX dump), not one found by a
-- 300 ms scan: the mod's loops held the game long enough to swallow keys
-- (firefly82, 2026-10-21).
local credits_path = nil

local function credits_widget()
    local w = credits_path and StaticFindObject(credits_path)
    if w and w:IsValid() then return w end
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

-- Backspace closes the credits as the game's Escape does: WBP_Credits_C is
-- an activatable widget with no back button of its own ("Nothing to go back
-- to", Casey, 2026-10-14).
function M.close()
    if not items then return false end
    local w = credits_widget()
    if not w then return false end
    w:DeactivateWidget()
    return true
end

function M.repeat_item()
    say_item(true)
end

-- The credits text is the scroll box's own rich text (CreditsScrollBox in
-- the CXX dump), read from that widget, not by searching every rich text in
-- the game.
local function credits_text(w)
    local box = w.CreditsScrollBox
    if not (box and box:IsValid()) then return nil end
    local RT = StaticFindObject("/Script/UMG.RichTextBlock")
    for i = 0, box:GetChildrenCount() - 1 do
        local c = box:GetChildAt(i)
        if c and c:IsValid() and RT and c:IsA(RT) then return c:GetText():ToString() end
    end
    return nil
end

local function opened(path)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return end
    credits_path = path
    local text = credits_text(w)
    if not text then
        print("[VoyagerAccess] credits: no text in the scroll box\n")
        return
    end
    local list = parse(text)
    if #list == 0 then return end
    items, index, shown_path = list, 1, path
    require("focus").park_focus()
    print(string.format("[VoyagerAccess] credits: %d items\n", #list))
    speech.say(string.format("Credits, %d entries. Up and Down to read, Escape to close.", #list), true)
    say_item(false)
end

local function closed(path)
    if path == credits_path then
        credits_path = nil
        items, index, shown_path = nil, nil, nil
    end
end

local hooked = false
local function hook_class(path)
    if hooked then return end
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return end
    local cpath = w:GetClass():GetFullName():match("^%S+%s+(.+)$")
    local function after(fn)
        return function(ctx)
            local okp, p = pcall(function() return ctx:get():GetFullName():match("^%S+%s+(.+)$") end)
            if okp and p then ExecuteInGameThread(function() pcall(fn, p) end) end
        end
    end
    local ok1 = pcall(RegisterHook, cpath .. ":BP_OnActivated", after(opened))
    local ok2 = pcall(RegisterHook, cpath .. ":BP_OnDeactivated", after(closed))
    hooked = ok1 and ok2
    print("[VoyagerAccess] credits: events " .. (hooked and "hooked" or "not all hooked") .. "\n")
    -- The first credits may have been activated before their class was
    -- hooked (it is hooked on the tick after the game makes the widget).
    if w:IsInViewport() then opened(path) end
end
M.parse = parse

function M.install()
    require("popups").on_widget("WBP_Credits_C", hook_class)
    for _, w in ipairs(FindAllOf("WBP_Credits_C") or {}) do
        local p = w:IsValid() and w:GetFullName():match("^%S+%s+(.+)$")
        if p and p:find("^/Engine/Transient%.") then
            pcall(hook_class, p)
            if w:IsInViewport() then pcall(opened, p) end
            break
        end
    end
end

return M
