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
            if amount ~= "" then out[#out + 1] = amount .. " " .. res end
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
            return "Add work team" .. (crew and (". Costs " .. crew .. " crew") or "") .. (teams and (". " .. teams) or "") .. "."
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
    local ok, sel = pcall(function() return b:GetSelected() end)
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
        if rp and rp:sub(1, #mp) == mp and screen.shown(r) then
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
                        local t = M.patients_text()
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
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- Radial build menus show costs with the same widgets (focus.lua).
M.costs_under = costs_under

return M
