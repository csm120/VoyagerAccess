-- What is actually on screen. IsVisible() alone over-reports: a widget is
-- shown only if it and every ancestor (across WidgetTree boundaries) are
-- visible, and a WidgetSwitcher shows only its active page while keeping
-- the others Visible. Proven 2026-10-10: main menu went from 190 texts to
-- the 11 really on screen.

local M = {}

local SWITCHER, WIDGET = nil, nil

local function valid(o)
    return o ~= nil and type(o) == "userdata" and o.IsValid ~= nil and o:IsValid()
end
M.valid = valid

local function hidden_by_switcher(parent, node)
    SWITCHER = SWITCHER or StaticFindObject("/Script/UMG.WidgetSwitcher")
    if not parent:IsA(SWITCHER) then return false end
    local active = parent:GetActiveWidget()
    return not (valid(active) and active:GetFullName() == node:GetFullName())
end

local function shown_unsafe(w, stop)
    WIDGET = WIDGET or StaticFindObject("/Script/UMG.Widget")
    local node, hops = w, 0
    local stop_name = stop and stop:GetFullName()
    while valid(node) and hops < 64 do
        hops = hops + 1
        if stop_name and node:GetFullName() == stop_name then return true end
        if not node:IsVisible() then return false end
        local parent = node:GetParent()
        if valid(parent) then
            if hidden_by_switcher(parent, node) then return false end
            node = parent
        else
            local tree = node:GetOuter()
            local owner = valid(tree) and tree:GetOuter() or nil
            if valid(owner) and owner:IsA(WIDGET) then
                node = owner
            else
                return true
            end
        end
    end
    return true
end

-- With stop, only up to that widget (not including it): a new room's hull
-- widget is Hidden while its own state texts are right (VM, 2026-10-17).
function M.shown(w, stop)
    local ok, result = pcall(shown_unsafe, w, stop)
    return ok and result
end

-- True when widget w sits inside the widget whose path is target_path.
-- Path prefix first; then the parents, crossing widget trees, because
-- widgets the game makes at runtime often have the game instance as their
-- outer, so their path is not under their window (the campaign's hero
-- cards, "0 heroes", VM, 2026-10-16).
local function inside_unsafe(w, target_path)
    WIDGET = WIDGET or StaticFindObject("/Script/UMG.Widget")
    local node, hops = w, 0
    while valid(node) and hops < 48 do
        hops = hops + 1
        local parent = node:GetParent()
        if valid(parent) then
            node = parent
        else
            local tree = node:GetOuter()
            local owner = valid(tree) and tree:GetOuter() or nil
            if not (valid(owner) and owner:IsA(WIDGET)) then return false end
            node = owner
        end
        local p = node:GetFullName():match("^%S+%s+(.+)$")
        if p == target_path then return true end
    end
    return false
end

function M.inside(w, target_path)
    local ok, p = pcall(function() return w:GetFullName():match("^%S+%s+(.+)$") end)
    if not ok or not p then return false end
    if p:sub(1, #target_path + 1) == target_path .. "." then return true end
    if not p:find("^/Engine/Transient%.") then return false end
    local ok2, r = pcall(inside_unsafe, w, target_path)
    return ok2 and r
end

-- All on-screen texts as a sorted list of "text" strings.
function M.texts()
    local items, seen = {}, {}
    for _, t in ipairs(FindAllOf("TextBlock") or {}) do
        if valid(t) and t:GetFullName():find(" /Engine/Transient.", 1, true) then
            local ok, s = pcall(function() return t:GetText():ToString() end)
            if ok and s ~= "" and not seen[s] and M.shown(t) then
                seen[s] = true
                items[#items + 1] = s
            end
        end
    end
    table.sort(items)
    return items
end

return M
