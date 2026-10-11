-- Main Engineering's Warp Core tab: a vertical stack of tier buttons,
-- Button_GrayMode at the bottom and Button_Tier1 to Button_Tier6 above.
-- Every button's only text is the shared "Gray Mode" label beneath the
-- stack, and Up and Down do not move between them (2026-10-11), so the
-- mod names them and moves focus itself. Levels from the construction
-- manager: selected 0 is Gray Mode, and tiers above the maximum selectable
-- level are locked (max 1 on 2026-10-11, when the quest asked for Tier 1).

local M = {}

local MODULE = "WBP_MainEngineeringModule_C"

-- The tier a button stands for (0 = Gray Mode), or nil.
local function level_of(path)
    if not (path and path:find(MODULE, 1, true)) then return nil end
    local name = path:match("([^%.]+)$")
    if name == "Button_GrayMode" then return 0 end
    local n = name:match("^Button_Tier(%d)$")
    return n and tonumber(n) or nil
end

function M.handles(path)
    return level_of(path) ~= nil
end

local function manager()
    return FindFirstOf("STVConstructionManager")
end

function M.label(path)
    local level = level_of(path)
    local text = level == 0 and "Gray Mode" or ("Tier " .. level)
    local cm = manager()
    if cm and cm:IsValid() then
        local ok1, selected = pcall(function() return cm:GetSelectedWarpcoreLevel() end)
        local ok2, max = pcall(function() return cm:GetMaxSelectableWarpcoreLevel() end)
        if ok1 and selected == level then text = text .. ", selected" end
        if ok2 and level > max then text = text .. ", locked" end
    end
    return text
end

-- Up (dir 1) to the next tier up, Down (dir -1) to the next one down.
-- At either end the tier is said again, like any other list.
function M.move(path, dir)
    local level = level_of(path)
    if not level then return false end
    local target = level + dir
    if target < 0 or target > 6 then
        require("speech").say(M.label(path), true)
        return true
    end
    local name = target == 0 and "Button_GrayMode" or ("Button_Tier" .. target)
    local prefix = path:match("^(.*%.)[^%.]+$")
    local b = StaticFindObject(prefix .. name)
    if b and b:IsValid() then b:SetFocus() end
    return true
end

return M
