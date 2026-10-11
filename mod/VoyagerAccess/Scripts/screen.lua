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

local function shown_unsafe(w)
    WIDGET = WIDGET or StaticFindObject("/Script/UMG.Widget")
    local node, hops = w, 0
    while valid(node) and hops < 64 do
        hops = hops + 1
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

function M.shown(w)
    local ok, result = pcall(shown_unsafe, w)
    return ok and result
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
