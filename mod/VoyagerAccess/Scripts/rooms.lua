-- Room windows (WBP_RoomManagementV2): the header has the room's name,
-- level and state; the sections are separate module widgets (repair,
-- upgrade, power, description), each an STVRoomManagementWidgetModule,
-- not inside the window. Costs are WBP_ResourceCostWidget: an Amount text
-- and a ResourceImg whose material names the resource
-- ("MI_UI_Duranium_WhiteNoBG"). Read 2026-10-11 on the Transporter Room.

local screen = require("screen")

local M = {}

local RESOURCES = { BioNeuralGelPack = "bio-neural gel pack", SciencePoints = "science points",
    BorgNanites = "Borg nanites" }

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

local function text_of(w)
    if not (w and w:IsValid()) then return "" end
    local ok, s = pcall(function() return w:GetText():ToString() end)
    return ok and s or ""
end

local function plain(s)
    -- "[MAIN ENGINEERING]" marks a highlighted name; drop the brackets.
    return (s:gsub("<[^>]*>", ""):gsub("%[([^%]]*)%]", "%1"):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Buttons whose only text is a picture.
local open_window   -- defined below; the power button label needs it
local BUTTON_NAMES = { OpenSelectionButton = "Assign a hero" }

-- Texts on screen under path, as name -> text (first of each name).
local function texts_under(path)
    local by = {}
    local prefix = path .. "."
    for _, cls in ipairs({ "TextBlock", "RichTextBlock" }) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            local tp = t:IsValid() and path_of(t)
            if tp and tp:sub(1, #prefix) == prefix and screen.shown(t) then
                local name = tp:match("([^%.]+)$")
                if not by[name] then by[name] = plain(text_of(t)) end
            end
        end
    end
    return by
end

-- "14 Duranium, 50 Tritanium" from the cost widgets under path. The icon
-- is checked valid before it is read: an unchecked brush read across every
-- image crashed the game (2026-10-11).
local function costs_under(path)
    local out = {}
    local prefix = path .. "."
    for _, w in ipairs(FindAllOf("WBP_ResourceCostWidget_C") or {}) do
        local p = w:IsValid() and path_of(w)
        if p and p:sub(1, #prefix) == prefix and screen.shown(w) then
            local res = "resources"
            local img = w.ResourceImg
            if img and img:IsValid() then
                local ro = img.Brush.ResourceObject
                if ro and ro:IsValid() then
                    local raw = ro:GetFName():ToString():match("^MI_UI_(%a+)")
                    if raw then res = RESOURCES[raw] or raw end
                end
            end
            local amount = plain(text_of(w.Amount))
            if amount ~= "" then out[#out + 1] = amount .. " " .. res end
        end
    end
    return table.concat(out, ", ")
end

-- The module widget a button belongs to, or nil.
local function module_of(path)
    return path and path:match("^(.-WBP_%w+Module_C_%d+)%.") or nil
end

function M.is_module_button(path)
    local m = module_of(path)
    if not m then return false end
    local w = StaticFindObject(m)
    local base = StaticFindObject("/Script/STVoyager.STVRoomManagementWidgetModule")
    return w ~= nil and w:IsValid() and base ~= nil and w:IsA(base)
end

-- "Upgrade. Not possible: room is damaged. 1 work team, 15 cycles. Costs
-- 60 Duranium, 50 Tritanium, 1 bio-neural gel pack. Increases rewards ..."
function M.button_label(path, label)
    local m = module_of(path)
    local by = texts_under(m)
    local name = path:match("([^%.]+)$")
    if BUTTON_NAMES[name] and (label == nil or label == "Button" or label == "") then label = BUTTON_NAMES[name] end
    -- The power button says what it would do ("Switch Off"); say the room's
    -- state instead (Casey, 2026-10-11).
    -- After Enter, focus.lua speaks the new label, so the change is heard
    -- as "Life Support off".
    if name == "PowerToggleButton" and label then
        local w = open_window()
        local room = w and texts_under(path_of(w)).RoomNameText or "This room"
        local action = label:gsub("%.$", "")
        local lower = action:lower()
        -- Just the state (Casey, 2026-10-11): "Life Support on".
        if lower == "switch off" then label = room .. " on"
        elseif lower == "switch on" then label = room .. " off" end
    end
    local parts = { label }
    -- The Heroes tab: the skill this room uses, and what a hero gives.
    if by.HeroAttribute_TXT then parts[#parts + 1] = "Skill: " .. by.HeroAttribute_TXT end
    for k, v in pairs(by) do
        if k:find("^CommonTextBlock") and v:find("hero", 1, true) and not v:find(":%s*$") then
            parts[#parts + 1] = v
        end
    end
    for name, text in pairs(by) do
        if name:find("ImpossibleReason") and text ~= "" then
            parts[#parts + 1] = "Not possible: " .. text:lower()
        end
    end
    local needs = {}
    if by.RequiredWorkTeam_Text then
        local n = by.RequiredWorkTeam_Text
        needs[#needs + 1] = n .. (n == "1" and " work team" or " work teams")
    end
    if by.RequiredCycles_Text then
        local n = by.RequiredCycles_Text
        needs[#needs + 1] = n .. (n == "1" and " cycle" or " cycles")
    end
    if #needs > 0 then parts[#parts + 1] = table.concat(needs, ", ") end
    local costs = costs_under(m)
    if costs ~= "" then parts[#parts + 1] = "Costs " .. costs end
    if by.BenefitsText and by.BenefitsText ~= "" then
        parts[#parts + 1] = (by.BenefitsText:gsub("%+(%d)", "%1"))
    end
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    return table.concat(parts, ". ") .. "."
end

-- A hero in a room's hero list (WBP_RoomHeroSelectionButton). Its skills
-- are icons with numbers: each HeroStatSheet.AttributeDisplayN has
-- CurrentValue and an AttributeIcon whose material names the skill
-- ("MI_UI_Engineering"); the title text is empty. Read 2026-10-11 in Main
-- Engineering: Tom Paris Command 21, Engineering 11, Medicine 17.
-- "Command 21, Engineering 11, Medicine 17" from a hero's stat sheet; the
-- away team plaques use the same sheet.
function M.skills_of(sheet)
    local skills = {}
    if not (sheet and sheet:IsValid()) then return "" end
    for i = 1, 3 do
        local a = sheet["AttributeDisplay" .. i]
        if a and a:IsValid() and (a.CurrentValue or 0) > 0 then
            local skill = "Skill"
            local im = a.AttributeIcon
            if im and im:IsValid() then
                local ro = im.Brush.ResourceObject
                if ro and ro:IsValid() then skill = ro:GetFName():ToString():match("^MI_UI_(%a+)") or skill end
            end
            skills[#skills + 1] = skill .. " " .. a.CurrentValue
        end
    end
    return table.concat(skills, ", ")
end

function M.is_hero_button(path)
    return path ~= nil and path:find("WBP_RoomHeroSelectionButton_C_%d+") ~= nil
end

function M.hero_label(path)
    local bpath = path:match("^(.-WBP_RoomHeroSelectionButton_C_%d+)")
    local b = bpath and StaticFindObject(bpath)
    if not (b and b:IsValid()) then return nil end
    local plaque = b.HeroPlaque
    local parts = {}
    local name = plain(text_of(plaque.HeroNameText))
    local by = texts_under(bpath)
    local head = name
    if by.RankText then head = head .. ", " .. by.RankText:lower() end
    if by.TraitText and by.TraitText ~= "" then head = head .. ", " .. by.TraitText end
    parts[#parts + 1] = head
    local skills = M.skills_of(plaque.HeroStatSheet)
    if skills ~= "" then parts[#parts + 1] = skills end
    -- The bonus this hero gives the room ("+11% warp core repair rate.").
    for _, text in pairs(by) do
        if text:find("%%") then parts[#parts + 1] = (text:gsub("^%+", "Plus ")) end
    end
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    return table.concat(parts, ". ") .. "."
end

-- The open room window, or nil.
open_window = function()
    for _, w in ipairs(FindAllOf("WBP_RoomManagementV2_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then return w end
    end
    return nil
end

function M.window_open()
    return open_window() ~= nil
end

-- Left and Right in a room window switch its tabs (Management, Warp Core,
-- Heroes); the game only does that with a controller. The room window's own
-- SelectPreviousTab and SelectNextTab are UFunctions. The selected tab is
-- the tab button with GetSelected; its name is in ButtonName.
function M.switch_tab(dir)
    local w = open_window()
    if not w then return false end
    if dir < 0 then w:SelectPreviousTab() else w:SelectNextTab() end
    local wp = path_of(w) .. "."
    for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
        local p = b:IsValid() and path_of(b)
        if p and p:sub(1, #wp) == wp and p:find("TabButton", 1, true) and screen.shown(b) then
            local ok, sel = pcall(function() return b:GetSelected() end)
            if ok and sel then
                local name = plain(text_of(b.ButtonName))
                require("speech").say((name ~= "" and name or "Tab") .. " tab", true)
                return true
            end
        end
    end
    return true
end

-- Read when a room window opens: name, level, state, and the description.
function M.window_text(path)
    local by = texts_under(path)
    local head = by.RoomNameText or "Room"
    if by.RoomLevel then head = head .. ", " .. by.RoomLevel:gsub("^lvl 0*", "level ") end
    if by.ActiveText and by.ActiveText ~= "" then head = head .. ", " .. by.ActiveText:lower() end
    local out = { head }
    for _, w in ipairs(FindAllOf("WBP_RoomDescriptionModule_C") or {}) do
        if w:IsValid() and screen.shown(w) then
            local d = plain(text_of(w.DescriptionText))
            if d ~= "" then out[#out + 1] = d end
        end
    end
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

return M
