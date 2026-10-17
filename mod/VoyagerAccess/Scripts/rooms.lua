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
    s = require("text").prep(s)  -- icons beside numbers, list line breaks (text.lua)
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
    -- FindAllOf does not include subclasses: a room hero's bonus,
    -- HeroImpact_RichTXT ("+4 MORALE per CYCLE"), is a CommonRichTextBlock
    -- and was never read (Mess Hall, VM, 2026-10-15).
    for _, cls in ipairs({ "TextBlock", "RichTextBlock", "CommonTextBlock", "CommonRichTextBlock" }) do
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
            -- A cost you cannot pay is red (1, 0.09, 0.09; the others 0.75,
            -- 0.75, 0.8): "50 Duranium" with 38 in store (VM, 2026-10-17).
            local short = false
            pcall(function()
                local c = w.Amount.ColorAndOpacity.SpecifiedColor
                short = c.R > 0.9 and c.G < 0.3 and c.B < 0.3
            end)
            if amount ~= "" then out[#out + 1] = amount .. " " .. res .. (short and " not enough" or "") end
        end
    end
    return table.concat(out, ", ")
end

-- The module widget a button belongs to, or nil.
local function module_of(path)
    return path and path:match("^(.-WBP_%w+Module_C_%d+)%.") or nil
end

-- The Engineering Office's Work Team Info tab (first seen 2026-10-14): its
-- buttons' texts sit in separate blocks, and the mod read "+3, Remove, Work
-- Team" for Remove and never the team count or a team's activity.
-- WBP_EngineeringOffice_ManageWorkTeamsModule: RemoveWorkTeamButton,
-- AddWorkTeamButton (CrewAmount = crew it costs), WorkTeamCount "01/01".
-- WBP_WorkTeamInfo, one per team: WorkTeamID, WorkTeamActivity and an
-- AssignHullButton (ActionText).
function M.workteam_label(path)
    if not path then return nil end
    local name = path:match("([^%.]+)$")
    local manage = path:match("^(.-WBP_EngineeringOffice_ManageWorkTeamsModule_C_%d+)%.")
    -- A team's row is inside the module, so it is checked first.
    if manage and not path:find("WBP_WorkTeamInfo_C_", 1, true) then
        local by = texts_under(manage)
        local have, total = (by.WorkTeamCount or ""):match("^0*(%d+)/0*(%d+)$")
        local teams = have and string.format("%s work %s of %s", have, have == "1" and "team" or "teams", total) or nil
        if name == "RemoveWorkTeamButton" then
            return "Remove work team" .. (teams and (". " .. teams) or "") .. "."
        elseif name == "AddWorkTeamButton" then
            local crew = texts_under(path).CrewAmount
            -- At its limit the game ignores the button and says nothing
            -- ("01/01", demo, VM, 2026-10-16).
            local full = have and total and tonumber(have) >= tonumber(total)
            return "Add work team" .. (full and ". Not possible: this office has all the work teams it can hold" or "")
                .. (crew and (". Costs " .. crew .. " crew") or "") .. (teams and (". " .. teams) or "") .. "."
        end
        return nil
    end
    local info = path:match("^(.-WBP_WorkTeamInfo_C_%d+)%.")
    if info then
        local by = texts_under(info)
        local action = by.ActionText and by.ActionText:gsub("^%l", string.upper) or "Assign"
        local id = by.WorkTeamID or "Work team"
        local activity = by.WorkTeamActivity and by.WorkTeamActivity:lower() or nil
        return id .. (activity and (", " .. activity) or "") .. ". " .. action .. "."
    end
    return nil
end

-- The Science Laboratory's Research & Analysis tab (2026-10-14): its
-- buttons were read with hidden texts ("remaining ..., open tech tree,
-- currently no research in progress"). ResearchButton and AnalysisButton
-- (WBP_ScienceLab_ResearchModule) have ResearchName, CyclesText and
-- OnClickAction_TXT; an unexplored find (WBP_RoomMgmt_Analyze_Button) has
-- AnalysisName and CyclesText.
local function paused_shown(path)
    local ok, paused = pcall(function()
        local b = StaticFindObject(path)
        return b and b:IsValid() and b.Paused_IMG and b.Paused_IMG:IsValid() and screen.shown(b.Paused_IMG)
    end)
    return ok and paused
end

function M.research_label(path)
    if not path then return nil end
    local name = path:match("([^%.]+)$")
    if path:find("WBP_ScienceLab_ResearchModule_C_%d+%.") and (name == "ResearchButton" or name == "AnalysisButton") then
        local by = texts_under(path)
        local kind = name == "ResearchButton" and "Research" or "Analysis"
        local label = kind .. ": " .. (by.ResearchName or "")
        if by.CyclesText and by.CyclesText:match("%d") then
            local n = by.CyclesText:gsub("^#", ""):gsub("^0+(%d)", "%1")
            label = label .. ", " .. n .. (n == "1" and " cycle left" or " cycles left")
        end
        -- Starting a research pauses the analysis: Paused_IMG shows and the
        -- cycles go hidden, so the row read as if it were running (VM,
        -- 2026-10-17).
        if paused_shown(path) then label = label .. ", paused" end
        if name == "ResearchButton" then
            label = label .. ". Enter opens the tech tree"
        elseif by.OnClickAction_TXT and by.OnClickAction_TXT ~= "" then
            label = label .. ". Enter: " .. by.OnClickAction_TXT
        end
        return label .. "."
    end
    -- The Workshop's Crafting tab is built the same way (2026-10-14):
    -- CraftingButton in WBP_Workshop_CraftModule, and one WBP_ItemButton
    -- per blueprint (ItemName, Duration in cycles, cost widgets). Its
    -- TextBlock_122 "Production on hold" counts as shown but is not on
    -- screen, so it is left out.
    if path:find("WBP_Workshop_CraftModule_C_%d+%.") and name == "CraftingButton" then
        local by = texts_under(path)
        local label = "Crafting: " .. (by.ResearchName or "")
        if paused_shown(path) then label = label .. ", paused" end
        if by.CyclesText and by.CyclesText:match("[1-9]") then
            local n = by.CyclesText:gsub("^#", ""):gsub("^0+(%d)", "%1")
            label = label .. ", " .. n .. (n == "1" and " cycle left" or " cycles left")
            if by.OnClickAction_TXT and by.OnClickAction_TXT ~= "" then
                label = label .. ". Enter: " .. by.OnClickAction_TXT
            end
        end
        -- With no blueprints the list below shows "currently no craftable
        -- blueprints" (only "currently no" is a text widget), and Down had
        -- nowhere to go without a word (VM, 2026-10-15).
        local mp = path:match("^(.-WBP_Workshop_CraftModule_C_%d+)%.")
        local none = false
        for _, text in pairs(mp and texts_under(mp) or {}) do
            if text:lower():find("^currently no%s+craftable") then none = true end
        end
        if none then label = label:gsub("%.$", "") .. ". No blueprints to craft" end
        return label .. "."
    end
    local function workshop_open()
        for _, m in ipairs(FindAllOf("WBP_Workshop_CraftModule_C") or {}) do
            if m:IsValid() and path_of(m):find("^/Engine/Transient%.") and screen.shown(m) then return true end
        end
        return false
    end
    if path:find("WBP_ItemButton_C_%d+$") and workshop_open() then
        local by = texts_under(path)
        local label = by.ItemName or "Item"
        local n = by.Duration
        if n and n:match("^%d+$") then label = label .. ", " .. n .. (n == "1" and " cycle" or " cycles") end
        local costs = costs_under(path)
        if costs ~= "" then label = label .. ", costs " .. costs end
        return label .. ". Enter crafts it."
    end
    if path:find("WBP_RoomMgmt_Analyze_Button_C_%d+$") then
        local by = texts_under(path)
        local label = "Unexplored: " .. (by.AnalysisName or "unknown")
        if by.CyclesText and by.CyclesText:match("%d") then label = label .. ", " .. by.CyclesText .. " cycles to analyze" end
        return label .. "."
    end
    return nil
end

-- The Mess Hall's ration buttons (WBP_Button_SelectableServing): TitleText
-- and a rich ContentText "<ColorNegative>-40</>" that the plain label left
-- out, so both read "..., Morale" with no number (2026-10-14).
function M.serving_label(path)
    if not (path and path:find("WBP_Button_SelectableServing_C_%d+$")) then return nil end
    local by = {}
    local prefix = path .. "."
    for _, cls in ipairs({ "TextBlock", "RichTextBlock", "CommonTextBlock", "CommonRichTextBlock" }) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            local tp = t:IsValid() and path_of(t)
            if tp and tp:sub(1, #prefix) == prefix and screen.shown(t) then
                by[tp:match("([^%.]+)$")] = plain(text_of(t))
            end
        end
    end
    if not by.TitleText then return nil end
    local label = by.TitleText
    if by.ContentText and by.ContentText ~= "" then
        label = label .. ", " .. (by.TextBlock_106 or "Morale"):lower() .. " " .. by.ContentText
    end
    -- The window describes only the ration in use: say it with that one.
    local b = StaticFindObject(path)
    -- Valid first: a null object's method can crash past pcall.
    local ok, sel = pcall(function() return b and b:IsValid() and b:GetSelected() end)
    if ok and sel then
        label = label .. ", selected"
        -- One widget can be found under two class names: keep one text per
        -- name, said description first, then per crew, then for all crew.
        local texts = {}
        for _, cls in ipairs({ "TextBlock", "RichTextBlock", "CommonTextBlock", "CommonRichTextBlock" }) do
            for _, t in ipairs(FindAllOf(cls) or {}) do
                local tp = t:IsValid() and path_of(t)
                -- Premium rations show their cost instead of a description.
                local name = tp and tp:match("([^%.]+)$") or ""
                local key = name:find("DescriptionText$") and 1 or (name == "FedCrewPerResourceText" and 2)
                    or (name == "RequiredResourceAmountForCrewText" and 3) or nil
                if tp and key and not texts[key] and tp:find("WBP_MessHall_ServingSizeModule_C_%d+%.") and screen.shown(t) then
                    local d = plain(text_of(t))
                    if d ~= "" then texts[key] = d end
                end
            end
        end
        for key = 1, 3 do
            if texts[key] then label = label .. ". " .. texts[key] end
        end
    end
    return label
end

-- The Work Team Info tab opens with nothing focused; the mod's window list
-- took Down while the game also moved focus to a team's button, both spoke,
-- and then Up and Down moved nowhere (2026-10-14). So its buttons get
-- explicit Up and Down rules in screen order (Remove, Add, each team) and
-- Remove gets real focus. Returns true when it focused something.
local NAV_UP, NAV_DOWN = 2, 3
function M.prepare_workteams()
    local list = {}
    for _, name in ipairs({ "RemoveWorkTeamButton", "AddWorkTeamButton" }) do
        for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
            if b:IsValid() and b:GetFName():ToString() == name and path_of(b):find("^/Engine/Transient%.") and screen.shown(b) then
                list[#list + 1] = b
            end
        end
    end
    if #list == 0 then return false end
    local teams = {}
    for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
        if b:IsValid() and b:GetFName():ToString() == "AssignHullButton" and screen.shown(b) then teams[#teams + 1] = b end
    end
    table.sort(teams, function(a, b) return path_of(a) < path_of(b) end)
    for _, b in ipairs(teams) do list[#list + 1] = b end
    for i = 1, #list do
        pcall(function()
            if list[i - 1] then list[i]:SetNavigationRuleExplicit(NAV_UP, list[i - 1]) else list[i]:SetNavigationRuleBase(NAV_UP, 3) end
            if list[i + 1] then list[i]:SetNavigationRuleExplicit(NAV_DOWN, list[i + 1]) else list[i]:SetNavigationRuleBase(NAV_DOWN, 3) end
        end)
    end
    list[1]:SetFocus()
    return list[1]:HasFocusedDescendants() or list[1]:HasKeyboardFocus()
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
    -- After a hero was chosen the slot still said "Assign a hero", so the
    -- assignment could not be confirmed (2026-10-14). The slot's plaque
    -- shows the hero's name only while one is assigned.
    if name == "OpenSelectionButton" and by.HeroNameText and by.HeroNameText ~= "" then
        label = "Assigned hero: " .. by.HeroNameText
        if by.HeroImpact_RichTXT and by.HeroImpact_RichTXT ~= "" then
            label = label .. ". " .. (by.HeroImpact_RichTXT:gsub("%.%s*$", ""))
        end
    end
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
        -- Dismantle and the power button name theirs differently
        -- (DestroyRoomInactiveReasonText, CantActivateReasonText): a room
        -- without life support read "Dismantle" as if it could be done and
        -- Enter did nothing (VM, 2026-10-15).
        if (name:find("ImpossibleReason") or name:find("InactiveReason") or name:find("CantActivateReason")) and text ~= "" then
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
    -- Dismantling gives resources back: "+15 Duranium, +15 Tritanium" read
    -- as "Costs +15 Duranium" (2026-10-14).
    if costs ~= "" and not costs:find("^%-?%d") then
        parts[#parts + 1] = "Returns " .. costs:gsub("%+", "")
    elseif costs ~= "" then
        parts[#parts + 1] = "Costs " .. costs
    end
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
        -- A hidden third box keeps the last hero's value: Harry Kim (two
        -- skills) was read with Janeway's "Science 22" (2026-10-14).
        if a and a:IsValid() and a:IsVisible() and (a.CurrentValue or 0) > 0 then
            local skill = "Skill"
            local im = a.AttributeIcon
            if im and im:IsValid() then
                local ro = im.Brush.ResourceObject
                if ro and ro:IsValid() then skill = ro:GetFName():ToString():match("^MI_UI_(%a+)") or skill end
            end
            -- The number shown (AttributeValue): an injured hero's is
            -- reduced, Joe Carey's Command 13 where CurrentValue said 26
            -- (away team selection, VM, 2026-10-17).
            local shown_value = nil
            pcall(function() shown_value = a.AttributeValue:GetText():ToString():match("^%d+$") end)
            skills[#skills + 1] = skill .. " " .. (shown_value or tostring(a.CurrentValue))
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
    -- Injured or Severely Injured over the portrait, as in the away team
    -- list (awaymission.lua plaque_text, 2026-10-17).
    pcall(function()
        local st = plaque.HeroRoomText
        if st and st:IsValid() and screen.shown(st) then
            local s = plain(text_of(st))
            if s ~= "" and s:sub(1, 1) ~= "#" and s:lower():find("injur") then head = name .. ", " .. s:lower() .. head:sub(#name + 1) end
        end
    end)
    parts[#parts + 1] = head
    local skills = M.skills_of(plaque.HeroStatSheet)
    if skills ~= "" then parts[#parts + 1] = skills end
    -- The bonus this hero gives the room ("+11% warp core repair rate.").
    for _, text in pairs(by) do
        if text:find("%%") then parts[#parts + 1] = (text:gsub("^%+", "Plus ")) end
    end
    -- "2 of 3": the list said nothing at either end, so there was no way to
    -- know how many heroes it had (Mess Hall, VM, 2026-10-15).
    pcall(function()
        local list = b:GetParent()
        local n, index = 0, nil
        for i = 0, list:GetChildrenCount() - 1 do
            local c = list:GetChildAt(i)
            if c and c:IsValid() and c:GetClass():GetFName():ToString() == "WBP_RoomHeroSelectionButton_C" and screen.shown(c) then
                n = n + 1
                if c:GetFullName() == b:GetFullName() then index = n end
            end
        end
        if index then parts[#parts + 1] = index .. " of " .. n end
    end)
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    return table.concat(parts, ". ") .. "."
end

-- The open room window, or nil.
open_window = function()
    -- A room window left open when the story switches to the System Map
    -- stays "shown" behind the map: Escape opened the pause menu and I named
    -- the room (demo, VM, 2026-10-15). Room windows are in front only in the
    -- ship view.
    local okm, map = pcall(function() return require("system").active() end)
    if okm and map then return nil end
    for _, w in ipairs(FindAllOf("WBP_RoomManagementV2_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then return w end
    end
    return nil
end

function M.window_open()
    return open_window() ~= nil
end

-- A combat ally on the Bridge's Combat Allies tab (WBP_CombatAllyButton):
-- it was read as "2, /, 200, 20, Upkeep, Recruitment, 35, Talaxian Ally"
-- (VM, 2026-10-15). Costs are WBP_CombatAllyCost_SingleResource widgets in
-- CraftingCostRoot (to recruit) or CraftingCostRoot_PerCycle (upkeep).
-- A Shuttlebay's shuttle buttons (WBP_Shuttle_Status_Button in a
-- WBP_ShuttleStatus): Build, Status (Maintenance) and Remove. Each shows only
-- the shuttle type; "Dismantle" is the hover label, so Enter on "Class 2
-- Shuttle" would have scrapped the ship's only shuttle (Q Trials, VM,
-- 2026-10-15). The costs beside it are what building takes or dismantling
-- gives back.
function M.shuttle_label(b, path)
    local entry = path:match("^(.+)%.WidgetTree_%d+%.[%w_]+$")
    local w = entry and StaticFindObject(entry)
    if not (w and w:IsValid()) then return nil end
    local name = path:match("([%w_]+)$")
    local kind = plain(text_of(w.Text_ShuttleType))
    if kind == "" or kind:sub(1, 1) == "#" then kind = "shuttle" end
    local costs = {}
    local prefix = entry .. "."
    for _, c in ipairs(FindAllOf("WBP_ShuttleCost_SingleResource_C") or {}) do
        local cp = c:IsValid() and path_of(c)
        if cp and cp:sub(1, #prefix) == prefix and screen.shown(c) then
            local amount = plain(text_of(c.ResourceAmount)):gsub("^[%+%-]", "")
            local res = "resources"
            pcall(function()
                local ro = c.ResourceImage.Brush.ResourceObject
                if ro and ro:IsValid() then res = ro:GetFName():ToString():match("^MI_UI_(%a-)_") or ro:GetFName():ToString():match("^MI_UI_(%a+)") or res end
            end)
            res = (res:gsub("(%l)(%u)", "%1 %2"))
            if amount:match("%d") then costs[#costs + 1] = amount .. " " .. res end
        end
    end
    local list = table.concat(costs, ", ")
    local parts
    if name == "RemoveButton" then
        parts = { "Dismantle " .. kind }
        if list ~= "" then parts[#parts + 1] = "Returns " .. list end
    elseif name == "BuildButton" then
        parts = { "Build " .. kind }
        if list ~= "" then parts[#parts + 1] = "Costs " .. list end
        local cycles = plain(text_of(w.RequiredCycles_Text))
        if cycles:match("^%d+$") then parts[#parts + 1] = cycles .. (cycles == "1" and " cycle" or " cycles") end
    else
        parts = { kind }
        local status = plain(text_of(w.StatusInfoText))
        if status ~= "" and status:sub(1, 1) ~= "#" then parts[#parts + 1] = status end
        local remaining = plain(text_of(w.RemainingTextBlock))
        if remaining:match("%d") then parts[#parts + 1] = remaining end
    end
    local ok, en = pcall(function() return b:GetIsEnabled() end)
    if ok and en == false then parts[#parts + 1] = "unavailable" end
    return table.concat(parts, ". ") .. "."
end

function M.ally_label(b)
    local name = plain(text_of(b.CombatAllyName))
    if name == "" then return nil end
    local power = plain(text_of(b.AllyCombatPower))
    local parts = { power:match("%d") and (name .. ", combat power " .. power) or name }
    local bp = path_of(b) .. "."
    local recruit, upkeep = {}, {}
    for _, w in ipairs(FindAllOf("WBP_CombatAllyCost_SingleResource_C") or {}) do
        local wp = w:IsValid() and path_of(w)
        if wp and wp:sub(1, #bp) == bp and screen.shown(w) then
            local amount = plain(text_of(w.ResourceAmount))
            local res = "resources"
            pcall(function()
                local ro = w.ResourceImage.Brush.ResourceObject
                if ro and ro:IsValid() then res = ro:GetFName():ToString():match("^MI_UI_(%a-)_") or res end
            end)
            res = (res:gsub("(%l)(%u)", "%1 %2")):lower()
            local par = ""
            pcall(function() par = w:GetParent():GetFName():ToString() end)
            if amount:match("%d") then
                local list = par:find("PerCycle", 1, true) and upkeep or recruit
                list[#list + 1] = amount .. " " .. res
            end
        end
    end
    if #recruit > 0 then parts[#parts + 1] = "Recruitment: " .. table.concat(recruit, ", ") end
    if #upkeep > 0 then parts[#parts + 1] = "Upkeep: " .. table.concat(upkeep, ", ") .. " per cycle" end
    local ok, en = pcall(function() return b:GetIsEnabled() end)
    if ok and en == false then parts[#parts + 1] = "unavailable" end
    return table.concat(parts, ". ") .. "."
end

-- Sickbay's Manage Patients tab: a table of patients (WBP_SickBayPatientInfo:
-- PatientName, Conditions, RecoveryTime) and an EfficiencyReport, none of it
-- focusable, so the tab said nothing but its name (VM, 2026-10-15).
-- "3 patients: Tharin K'Vek, injured, 10 cycles to recover; ...", or nil
-- when the tab is not showing.
function M.patients_text()
    local module = nil
    for _, w in ipairs(FindAllOf("WBP_SickBay_ManagePatientsModule_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then module = w end
    end
    if not module then return nil end
    local mp = path_of(module) .. "."
    local rows = {}
    for _, r in ipairs(FindAllOf("WBP_SickBayPatientInfo_C") or {}) do
        local rp = r:IsValid() and path_of(r)
        if rp and screen.inside(r, (mp:gsub("%.$", ""))) and screen.shown(r) then
            local i = 0
            pcall(function() i = r:GetParent():GetChildIndex(r) end)
            rows[#rows + 1] = { i = i, r = r }
        end
    end
    table.sort(rows, function(a, b) return a.i < b.i end)
    local items = {}
    for _, row in ipairs(rows) do
        local r = row.r
        local name = plain(text_of(r.PatientName))
        local cond = plain(text_of(r.Conditions)):lower()
        local cycles = plain(text_of(r.RecoveryTime))
        local item = name
        -- A star before a hero's name (Image_75; Chakotay, Harry Kim and
        -- Tom Paris among crew, VM, 2026-10-16).
        local okh, hero = pcall(function() return screen.shown(r.Image_75) end)
        if okh and hero then item = item .. ", hero" end
        if cond ~= "" then item = item .. ", " .. cond end
        if cycles:match("^%d+$") then
            item = item .. ", " .. cycles .. (cycles == "1" and " cycle" or " cycles") .. " to recover"
        end
        items[#items + 1] = item
    end
    local out = { #items == 0 and "No patients" or
        (#items .. (#items == 1 and " patient: " or " patients: ") .. table.concat(items, "; ")) }
    local report = plain(text_of(module.EfficiencyReport))
    if report ~= "" then out[#out + 1] = (report:gsub("%.%s*$", "")) end
    return table.concat(out, ". ") .. "."
end

-- A quarters room's Crew Info tab (WBP_CrewQuartersInteraction: CrewCount
-- "12/12", rows WBP_CrewMemberInfo with CrewName, Condition, Workplace, "-"
-- when there is none), none of it focusable, so only "Crew Info tab" was
-- said (Emergency quarters, VM, 2026-10-15). "Inhabitants 12 of 12: Jelan
-- K'Var, injured; Jacob Baker, Science Laboratory; ...", or nil.
-- Bio Laboratory tab (WBP_BioLab, built and opened in the campaign, VM,
-- 2026-10-16). Every amount is a number beside an icon, so the blueprint
-- read "(selected), +1, 20, 120": its product is ResourceIcon's material
-- (MI_UI_BioNeuralGelPack_white), its costs WBP_ResourceCostWidget
-- children (ResourceImg, Amount), Duration the cycles. ItemName_TXT keeps a
-- designer placeholder ("#Crystalline Nucleogenic Compound") and is hidden.
local function icon_of(img)
    local name = nil
    pcall(function()
        local r = img.Brush.ResourceObject
        if r and r:IsValid() then name = require("text").icon_name(r:GetFName():ToString()) end
    end)
    return name
end

local function amount_of(n, what)
    n = tostring(n or ""):gsub("^%+", "")
    if not what then return n end
    if n == "1" then what = what:gsub("s$", "") end
    return n .. " " .. what
end

function M.biolab_item_label(b)
    local parts = { amount_of(plain(text_of(b.ResourceAmount)), icon_of(b.ResourceIcon) or "item") }
    if screen.shown(b.Selected_TXT) then parts[#parts + 1] = "selected" end
    if screen.shown(b.ProdOnHold_Container) then parts[#parts + 1] = "on hold" end
    local costs = {}
    pcall(function()
        local root = b.CraftingCostRoot
        for i = 0, root:GetChildrenCount() - 1 do
            local c = root:GetChildAt(i)
            if c and c:IsValid() and screen.shown(c) then
                costs[#costs + 1] = amount_of(plain(text_of(c.Amount)), icon_of(c.ResourceImg))
            end
        end
    end)
    local out = table.concat(parts, ", ")
    if #costs > 0 then out = out .. ". Costs " .. table.concat(costs, ", ") end
    local d = plain(text_of(b.Duration))
    if d:match("^%d+$") then out = out .. ". " .. amount_of(d, "cycles") end
    return out
end

-- The crafting slot at the top of the tab, or nil when the tab is not shown.
function M.biolab_text()
    local lab = nil
    for _, w in ipairs(FindAllOf("WBP_BioLab_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then lab = w end
    end
    if not lab then return nil end
    if screen.shown(lab.NoRequirementYet_Crafting_Overlay) then return "Crafting: nothing" end
    local item = amount_of(plain(text_of(lab.ResourceAmount)), icon_of(lab.ResourceIcon) or "item")
    local out = "Crafting " .. item
    if screen.shown(lab.Paused_IMG) or screen.shown(lab.ProdOnHold_Container) then out = out .. ", on hold" end
    local left = plain(text_of(lab.RemainigCyclesCount_Text))
    if left:match("^%d+$") then out = out .. ", " .. amount_of(left, "cycles") .. " left" end
    return out .. "."
end

-- The Engineering Office's Work Team Info tab: "Hull Repair rate per
-- cycle" with +3 (HullRepairEffectText) and -1 beside a duranium icon
-- (WBP_ResourceChangeDisplay), never read (hull at 9 and falling, VM,
-- 2026-10-16). Said with the ship's hull from the header.
function M.workteams_text()
    local m = nil
    for _, w in ipairs(FindAllOf("WBP_EngineeringOffice_ManageWorkTeamsModule_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then m = w end
    end
    if not m then return nil end
    local out = {}
    local rate = plain(text_of(m.HullRepairEffectText))
    if rate:match("%d") then
        local s = "Hull repair per cycle " .. rate .. " hull"
        local okc, cost = pcall(function()
            local d = m.WBP_ResourceChangeDisplay
            if not screen.shown(d) then return nil end
            return plain(text_of(d.AmountText)) .. " " .. (icon_of(d.ResourceIcon) or "")
        end)
        if okc and cost and cost:match("%d") then s = s .. ", " .. cost:gsub("%s+$", "") end
        out[#out + 1] = s
    end
    pcall(function()
        for _, h in ipairs(FindAllOf("WBP_HullIntegrity_C") or {}) do
            if h:IsValid() and screen.shown(h) then
                local cur, per = plain(text_of(h.CurrentHullValue)), plain(text_of(h.HullValuePerCycle))
                if cur:match("%d") then
                    out[#out + 1] = "Hull " .. cur .. (per:match("%d") and (", " .. per .. " per cycle") or "")
                end
            end
        end
    end)
    return #out > 0 and (table.concat(out, ". ") .. ".") or nil
end

-- The Bridge's Combat Allies tab (WBP_Bridge_CombatAllyModule): "Combat
-- ally. Currently no combat allies recruited. Recruit. Currently no
-- recruitable combat allies", none of it read (demo, VM, 2026-10-16). Its
-- texts in screen order; allies themselves are buttons in the window list.
-- Texts in widget-tree order, which follows the layout (the shared reader
-- gave both headings first, then both messages). "= COMBAT POWER" is an
-- icon's legend and is left out.
local function tree_texts(root)
    local out = {}
    local function walk(w, depth)
        if depth > 30 or not (w and w:IsValid()) or not screen.shown(w) then return end
        local okt, s = pcall(function() return w:GetText():ToString() end)
        if okt and type(s) == "string" then
            s = plain(s)
            if s ~= "" and not s:match("^=") then out[#out + 1] = s end
            return
        end
        local okn, n = pcall(function() return w:GetChildrenCount() end)
        if okn and type(n) == "number" then
            for i = 0, n - 1 do
                local okc, c = pcall(function() return w:GetChildAt(i) end)
                if okc then walk(c, depth + 1) end
            end
            return
        end
        local okr, r = pcall(function() return w.WidgetTree.RootWidget end)
        if okr and r then walk(r, depth + 1) end
    end
    walk(root, 0)
    return out
end

function M.allies_text()
    for _, w in ipairs(FindAllOf("WBP_Bridge_CombatAllyModule_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
            local parts = tree_texts(w)
            if #parts > 0 then
                for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", ""):gsub("^%l", string.upper) end
                return table.concat(parts, ". ") .. "."
            end
        end
    end
    return nil
end

function M.crew_text()
    local module = nil
    for _, w in ipairs(FindAllOf("WBP_CrewQuartersInteraction_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then module = w end
    end
    if not module then return nil end
    local mp = path_of(module) .. "."
    local rows = {}
    for _, r in ipairs(FindAllOf("WBP_CrewMemberInfo_C") or {}) do
        local rp = r:IsValid() and path_of(r)
        if rp and screen.inside(r, (mp:gsub("%.$", ""))) and screen.shown(r) then
            local i = 0
            pcall(function() i = r:GetParent():GetChildIndex(r) end)
            rows[#rows + 1] = { i = i, r = r }
        end
    end
    table.sort(rows, function(a, b) return a.i < b.i end)
    local items = {}
    for _, row in ipairs(rows) do
        local r = row.r
        local item = plain(text_of(r.CrewName))
        local cond = plain(text_of(r.Condition))
        local work = plain(text_of(r.Workplace))
        if cond ~= "" and cond ~= "-" then item = item .. ", " .. cond:lower() end
        if work ~= "" and work ~= "-" then item = item .. ", " .. work end
        if item ~= "" then items[#items + 1] = item end
    end
    local count = plain(text_of(module.CrewCount))
    local a, b = count:match("^(%d+)%s*/%s*(%d+)$")
    local head = a and ("Inhabitants " .. a .. " of " .. b) or "Inhabitants"
    if #items == 0 then return head .. "." end
    return head .. ": " .. table.concat(items, "; ") .. "."
end

-- The Aeroshuttle Bay's Trading tab: "New trade offer in 14 cycles.
-- Awaiting new trade offers" twice, none of it focusable; only "Trading
-- tab" was said (Q Trials, VM, 2026-10-15). Its texts in order, each once;
-- offers that are buttons are read as focus reaches them.
function M.trading_text()
    local module = nil
    for _, w in ipairs(FindAllOf("WBP_AeroShuttleBayModule_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then module = w end
    end
    if not module then return nil end
    local mp = path_of(module) .. "."
    local out, seen, done = {}, {}, {}
    for _, cls in ipairs({ "TextBlock", "CommonTextBlock", "RichTextBlock", "CommonRichTextBlock" }) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            local tp = t:IsValid() and path_of(t)
            -- A CommonTextBlock is found as a TextBlock too: "4 slots" for 2.
            -- Offers are read whole below, not as their loose parts.
            if tp and not done[tp] and tp:sub(1, #mp) == mp and screen.shown(t) and not tp:find("Button", 1, true)
                and not tp:find("TradeOff", 1, true) then
                done[tp] = true
                local s = plain(text_of(t))
                if s ~= "" and s:sub(1, 1) ~= "#" then
                    local key = s:lower()
                    if seen[key] then seen[key] = seen[key] + 1 else seen[key] = 1 out[#out + 1] = s end
                end
            end
        end
    end
    local offers = 0
    for _, o in ipairs(FindAllOf("WBP_AeroShuttleBay_TradeOffer_C") or {}) do
        local op = o:IsValid() and path_of(o)
        if op and screen.inside(o, (mp:gsub("%.$", ""))) and screen.shown(o) then offers = offers + 1 end
    end
    if offers > 0 then
        out[#out + 1] = offers .. (offers == 1 and " offer" or " offers") .. "; Enter on an offer reaches Trade and Dismiss"
        seen[out[#out]:lower()] = 1
    end
    if #out == 0 then return nil end
    for i, s in ipairs(out) do
        local n = seen[s:lower()]
        -- Capitals only for the empty slots' "AWAITING NEW TRADE OFFERS".
        if s == s:upper() then s = s:sub(1, 1) .. s:sub(2):lower() end
        out[i] = (s:gsub("%.%s*$", "")) .. (n > 1 and (", " .. n .. " slots") or "")
    end
    return table.concat(out, ". ") .. "."
end

-- An Aeroshuttle trade offer (WBP_AeroShuttleBay_TradeOffer): its focus
-- label was "TRADE, DISMISS, Offer, Trade Duration 24, Voyager, missing
-- resources, 14, Expires in, Trade Offer 01" (VM, 2026-10-15). The two
-- sides are WBP_AeroShuttleBay_TradeOffer_Resources widgets in its
-- TradeOfferBox (what the trader gives) and VoyTradeOfferBox (what Voyager
-- pays); they are found by climbing their parents to this offer.
local function belongs_to(w, target)
    local node = w
    for _ = 1, 16 do
        local okp, p = pcall(function() return node:GetParent() end)
        if okp and p and p:IsValid() then
            node = p
        else
            local oko, tree = pcall(function() return node:GetOuter() end)
            if not (oko and tree and tree:IsValid()) then return false end
            local okw, owner = pcall(function() return tree:GetOuter() end)
            if not (okw and owner and owner:IsValid()) then return false end
            node = owner
        end
        if node == target or (node:IsValid() and target:IsValid() and node:GetFullName() == target:GetFullName()) then return true end
    end
    return false
end

function M.trade_offer_label(offer)
    local gives, pays = {}, {}
    for _, r in ipairs(FindAllOf("WBP_AeroShuttleBay_TradeOffer_Resources_C") or {}) do
        if r:IsValid() and screen.shown(r) and belongs_to(r, offer) then
            local amount = plain(text_of(r.ResourceAmount)):gsub("[%s%+%-]", "")
            -- "04 Dilithium" (VM, 2026-10-16).
            amount = amount:gsub("^0+(%d)", "%1")
            local res = "resources"
            pcall(function()
                local ro = r.ResourceImage.Brush.ResourceObject
                if ro and ro:IsValid() then res = ro:GetFName():ToString():match("^MI_UI_(%a-)_") or res end
            end)
            res = res:gsub("(%l)(%u)", "%1 %2")
            local side = ""
            pcall(function() side = r:GetParent():GetFName():ToString() end)
            if amount ~= "" then
                local list = side:find("^Voy") and pays or gives
                list[#list + 1] = amount .. " " .. res
            end
        end
    end
    local out = { plain(text_of(offer.TradeOfferIndex)) ~= "" and plain(text_of(offer.TradeOfferIndex)) or "Trade offer" }
    out[1] = out[1]:gsub(" 0(%d)$", " %1")
    if #pays > 0 then out[#out + 1] = "You give " .. table.concat(pays, ", ") end
    if #gives > 0 then out[#out + 1] = "You get " .. table.concat(gives, ", ") end
    local dur = plain(text_of(offer.DurationText)):match("(%d+)")
    -- A trade under way shows "16 remaining" and hides its expiry ("Expires
    -- in 00 cycles" was read, VM, 2026-10-16).
    local under_way = false
    pcall(function() under_way = screen.shown(offer.remainingText) end)
    if dur and under_way and tonumber(dur) == 0 then
        out[#out + 1] = "Trade done; Enter reaches Collect"
    elseif dur and under_way then
        out[#out + 1] = "Trade under way, " .. tonumber(dur) .. (tonumber(dur) == 1 and " cycle" or " cycles") .. " left"
    elseif dur then
        out[#out + 1] = "Takes " .. tonumber(dur) .. (tonumber(dur) == 1 and " cycle" or " cycles")
    end
    local exp = ""
    pcall(function() if screen.shown(offer.ExpireTimeTextBox) then exp = plain(text_of(offer.ExpireTimeTextBox)) end end)
    if exp:match("^%d+$") then out[#out + 1] = "Expires in " .. tonumber(exp) .. (tonumber(exp) == 1 and " cycle" or " cycles") end
    -- Hidden once the trade is possible, and then still holding its
    -- designer text: "Not possible: #trade blocked text" (VM, 2026-10-16).
    local blocked = ""
    pcall(function() if screen.shown(offer.TradeBlockedText) then blocked = plain(text_of(offer.TradeBlockedText)) end end)
    if blocked ~= "" and not blocked:find("^#") then out[#out + 1] = "Not possible: " .. blocked:lower() end
    return table.concat(out, ". ") .. "."
end

-- Up and Down between trade offers: the game has no keyboard route from one
-- offer to the next (two offers, VM, 2026-10-15). True when handled.
function M.trade_offer_step(path, dir)
    if not (path and path:find("WBP_AeroShuttleBay_TradeOff", 1, true)) then return false end
    local cur = StaticFindObject(path)
    if not (cur and cur:IsValid() and cur:GetClass():GetFName():ToString() == "WBP_AeroShuttleBay_TradeOffer_C") then return false end
    local prefix = path:match("^(.+%.)[^%.]+$")
    local list = {}
    for _, o in ipairs(FindAllOf("WBP_AeroShuttleBay_TradeOffer_C") or {}) do
        local op = o:IsValid() and path_of(o)
        if op and op:sub(1, #prefix) == prefix and screen.shown(o) then list[#list + 1] = { o = o, p = op } end
    end
    table.sort(list, function(a, b)
        return (tonumber(a.p:match("_(%d+)$")) or 0) < (tonumber(b.p:match("_(%d+)$")) or 0)
    end)
    for i, e in ipairs(list) do
        if e.p == path then
            local nxt = list[i + dir]
            if nxt then nxt.o:SetFocus() else require("speech").say(M.trade_offer_label(cur), true) end
            return true
        end
    end
    return false
end

-- Left and Right in a room window switch its tabs (Management, Warp Core,
-- Heroes); the game only does that with a controller. The room window's own
-- SelectPreviousTab and SelectNextTab are UFunctions. The selected tab is
-- the tab button with GetSelected; its name is in ButtonName.
function M.switch_tab(dir)
    local w = open_window()
    if not w then return false end
    -- Back on the Bridge's Combat Allies tab only "Combat Allies tab" was
    -- said: focus had stayed on the ally the whole time, so nothing changed
    -- to speak. The item is said again when focus did not move.
    local okb, before = pcall(function() return require("focus").current_path() end)
    M.tab_switched_at = os.clock()
    if dir < 0 then w:SelectPreviousTab() else w:SelectNextTab() end
    local wp = path_of(w) .. "."
    for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
        local p = b:IsValid() and path_of(b)
        if p and p:sub(1, #wp) == wp and p:find("TabButton", 1, true) and screen.shown(b) then
            local ok, sel = pcall(function() return b:GetSelected() end)
            if ok and sel then
                local name = plain(text_of(b.ButtonName))
                name = (name ~= "" and name or "Tab"):gsub("^%l", string.upper)
                require("speech").say(name .. " tab", true)
                -- The tab's page is filled after the switch.
                ExecuteInGameThreadWithDelay(300, function()
                    pcall(function()
                        -- Only on that tab: just after leaving it, its page
                        -- still counts as shown (review, 2026-10-15).
                        local t = name:lower():find("patient", 1, true) and M.patients_text()
                            or name:lower():find("trading", 1, true) and M.trading_text()
                            or name:lower():find("crew", 1, true) and M.crew_text()
                            or name:lower():find("bio", 1, true) and M.biolab_text()
                            or name:lower():find("work team", 1, true) and M.workteams_text()
                            or name:lower():find("allies", 1, true) and M.allies_text()
                        if t then require("speech").say(t, false) end
                    end)
                    pcall(function()
                        local f = require("focus")
                        local label = f.current_label()
                        if okb and before and f.current_path() == before and label and label ~= "" then
                            require("speech").say(label, false)
                        end
                    end)
                end)
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
    -- The energy it uses, a number beside a lightning icon in the header
    -- (not read until 2026-10-14, when power ran short).
    local energy = by.EnergyConsumptionText
    if energy and energy:match("^%d+$") then head = head .. ", uses " .. energy .. " energy" end
    local out = { head }
    for _, w in ipairs(FindAllOf("WBP_RoomDescriptionModule_C") or {}) do
        if w:IsValid() and screen.shown(w) then
            local d = plain(text_of(w.DescriptionText))
            if d ~= "" then out[#out + 1] = d end
        end
    end
    -- Sickbay opens on Manage Patients.
    local okp, patients = pcall(M.patients_text)
    if okp and patients then out[#out + 1] = patients end
    -- Quarters open on Crew Info.
    local okc, crew = pcall(M.crew_text)
    if okc and crew then out[#out + 1] = crew end
    -- The tab can show a moment after the window: a working Sickbay with
    -- five patients said only "Sick bay, level 1, active, uses 7 energy"
    -- (VM, 2026-10-16). Read it then, after the header.
    if not (okp and patients) and not (okc and crew) then
        ExecuteInGameThreadWithDelay(600, function()
            pcall(function()
                local t = M.patients_text() or M.crew_text() or M.biolab_text() or M.workteams_text() or M.allies_text()
                if t then require("speech").say(t, false) end
            end)
        end)
    end
    -- A cargo bay's "Stock" bar (WBP_Cargo_FillPercentModule, FillPercentBar),
    -- a bar with no number, never read (room widget scan, VM, 2026-10-15).
    -- Its outer is the game instance, not the window; one room window is
    -- open at a time, so a shown one is this window's.
    pcall(function()
        for _, w in ipairs(FindAllOf("WBP_Cargo_FillPercentModule_C") or {}) do
            if w:IsValid() and screen.shown(w) then
                local pct = math.floor(w.FillPercentBar.Percent * 100 + 0.5)
                out[#out + 1] = "Stock " .. pct .. " percent full"
                break
            end
        end
    end)
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- Radial build menus show costs with the same widgets (focus.lua).
M.costs_under = costs_under

return M
