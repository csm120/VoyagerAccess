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

-- The game must not also move between tiers on Up and Down: with rules
-- from focus.lua's row wiring it did, and one press went two tiers
-- (2026-10-14). EUINavigationRule Stop = 3; EUINavigation Up = 2, Down = 3.
local function stop_game_navigation(path)
    local prefix = path:match("^(.*%.)[^%.]+$")
    for _, name in ipairs({ "Button_GrayMode", "Button_Tier1", "Button_Tier2", "Button_Tier3",
                            "Button_Tier4", "Button_Tier5", "Button_Tier6" }) do
        local b = StaticFindObject(prefix .. name)
        if b and b:IsValid() then
            pcall(function()
                b:SetNavigationRuleBase(2, 3)
                b:SetNavigationRuleBase(3, 3)
            end)
        end
    end
end

function M.label(path)
    local level = level_of(path)
    pcall(stop_game_navigation, path)
    local text = level == 0 and "Gray Mode" or ("Tier " .. level)
    local cm = manager()
    if cm and cm:IsValid() then
        local ok1, selected = pcall(function() return cm:GetSelectedWarpcoreLevel() end)
        local ok2, max = pcall(function() return cm:GetMaxSelectableWarpcoreLevel() end)
        if ok1 and selected == level then
            text = text .. ", selected"
            -- What the running tier makes and burns (STVWarpcoreInfo); the
            -- tiers never said their energy or fuel (open since 2026-10-14).
            -- Only the active tier's figures exist; the other tiers' panels
            -- hold designer placeholders ("+999").
            pcall(function()
                -- WarpcoreDeuteriumInput read 5 where the panel said -24;
                -- the panel's figure is energy over energy per deuterium.
                local info = cm:GetWarpcoreInfo()
                local e, per = info.WarpcoreEnergyOutputMax, cm:GetEnergyProducedPerDeuterium()
                if level > 0 and e and e > 0 and per and per > 0 then
                    text = text .. string.format(", makes %d energy, burns %d deuterium per cycle", e, math.ceil(e / per))
                end
            end)
        end
        if ok2 and level > max then text = text .. ", locked" end
    end
    return text
end

-- Enter on a tier the game will not run (Tier 1 with 16 deuterium, Gray
-- Mode, 2026-10-14) did nothing and said nothing: say so, with the
-- deuterium on hand, once the click has had time to take.
function M.after_enter(path)
    local level = level_of(path)
    ExecuteInGameThreadWithDelay(600, function()
        pcall(function()
            local cm = manager()
            if not (cm and cm:IsValid()) then return end
            if cm:GetSelectedWarpcoreLevel() == level then return end
            local name = level == 0 and "Gray Mode" or ("Tier " .. level)
            local deut = nil
            pcall(function() deut = cm:GetWarpcoreInfo().DeuteriumAmount end)
            require("speech").say(name .. " did not engage" .. (deut and (". Deuterium " .. deut) or "") .. ".", true)
        end)
    end)
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
