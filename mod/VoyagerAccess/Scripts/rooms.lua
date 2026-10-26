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
-- stop (optional): texts count as shown when they are shown inside that
-- widget, for a window still fading in.
local function search_texts_under(path, stop)
    local by = {}
    local prefix = path .. "."
    -- FindAllOf does not include subclasses: a room hero's bonus,
    -- HeroImpact_RichTXT ("+4 MORALE per CYCLE"), is a CommonRichTextBlock
    -- and was never read (Mess Hall, VM, 2026-10-15).
    for _, cls in ipairs({ "TextBlock", "RichTextBlock", "CommonTextBlock", "CommonRichTextBlock" }) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            local tp = t:IsValid() and path_of(t)
            if tp and tp:sub(1, #prefix) == prefix and screen.shown(t, stop) then
                local name = tp:match("([^%.]+)$")
                if not by[name] then by[name] = plain(text_of(t)) end
            end
        end
    end
    return by
end

-- The same, from the window's own widget tree (screen.walk): the search
-- above held the game for over 100 ms on every room window read (timing
-- log, VM, 2026-10-21). Only texts whose path is under the window count,
-- as before. stop: the window itself while a parent fades in.
local TEXT_BASES = nil
local function tree_texts_under(path, stop)
    local by = {}
    local root = StaticFindObject(path)
    if not (root and root:IsValid()) then return by end
    local inside = stop ~= nil and stop:GetFullName() == root:GetFullName()
    if not inside and not screen.shown(root, stop) then return by end
    -- The window not visible yet: the search, which walks no children (a
    -- hidden panel's children crashed the game once, probe 2026-10-20).
    if inside and not root:IsVisible() then return search_texts_under(path, stop) end
    TEXT_BASES = TEXT_BASES or { StaticFindObject("/Script/UMG.TextBlock"), StaticFindObject("/Script/UMG.RichTextBlock") }
    local prefix = path .. "."
    screen.walk(root, function(w)
        local is_text = false
        for _, c in ipairs(TEXT_BASES) do
            if c and c:IsValid() and w:IsA(c) then is_text = true break end
        end
        if not is_text then return false end
        local tp = path_of(w)
        if tp and tp:sub(1, #prefix) == prefix then
            local name = tp:match("([^%.]+)$")
            if not by[name] then by[name] = plain(text_of(w)) end
        end
        return true
    end, { no_root_check = inside, no_lists = true })
    return by
end

local TREECHECK = (function()
    local f = io.open((os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\treecheck", "r")
    if f then f:close() return true end
    return false
end)()
local tree_logged = {}
local function texts_under(path, stop)
    local t0 = os.clock()
    local by = tree_texts_under(path, stop)
    if not TREECHECK then return by end
    local t1 = os.clock()
    local old = search_texts_under(path, stop)
    local t2 = os.clock()
    local diffs = {}
    for k, v in pairs(old) do if by[k] ~= v then diffs[#diffs + 1] = k .. ": [" .. tostring(v) .. "] tree [" .. tostring(by[k]) .. "]" end end
    for k, v in pairs(by) do if old[k] == nil then diffs[#diffs + 1] = k .. ": only tree [" .. tostring(v) .. "]" end end
    table.sort(diffs)
    local key = table.concat(diffs, "; ")
    if not tree_logged[key] then
        tree_logged[key] = true
        print(string.format("[VoyagerAccess] treecheck: room texts search %d ms tree %d ms, %s\n",
            math.floor((t2 - t1) * 1000 + 0.5), math.floor((t1 - t0) * 1000 + 0.5),
            #diffs == 0 and "same" or ("DIFFERS " .. key:sub(1, 600))))
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
            -- "7 bio-neural gel pack" (demo, VM, 2026-10-22).
            if res == "bio-neural gel pack" and amount ~= "1" then res = "bio-neural gel packs" end
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
        local activity = by.WorkTeamActivity and require("tr").lower(by.WorkTeamActivity) or nil
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
        -- "Research" is looked up by name: it is off the line-wide pass
        -- (tr.lua, firefly82, 2026-10-24).
        local kind = name == "ResearchButton" and require("tr").word("Research") or "Analysis"
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
            label = label .. require("hints").text("lab_tree", ". Enter opens the tech tree")
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
        local crafting = by.CyclesText and by.CyclesText:match("[1-9]") ~= nil
        if crafting then
            local n = by.CyclesText:gsub("^#", ""):gsub("^0+(%d)", "%1")
            label = label .. ", " .. n .. (n == "1" and " cycle left" or " cycles left")
            if by.OnClickAction_TXT and by.OnClickAction_TXT ~= "" then
                label = label .. ". Enter: " .. by.OnClickAction_TXT
            end
        end
        -- With no blueprints the list below shows "currently no craftable
        -- blueprints" (only "currently no" is a text widget), and Down had
        -- nowhere to go without a word (VM, 2026-10-15).
        -- By the blueprint buttons shown, not the words: the text matched
        -- with two blueprints listed ("No blueprints to craft" beside Bio-
        -- Molecular Disruptor and Torpedoes, VM, 2026-10-17), and it was
        -- English only.
        local none = true
        for _, ib in ipairs(FindAllOf("WBP_ItemButton_C") or {}) do
            if ib:IsValid() and path_of(ib):find("^/Engine/Transient%.") and screen.shown(ib) then none = false end
        end
        -- Not while crafting: the list is hidden then, and "Crafting:
        -- Torpedo, 8 cycles left... No blueprints to craft" was read (VM,
        -- 2026-10-17).
        if none and not crafting then label = label:gsub("%.$", "") .. ". No blueprints to craft" end
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
        local label = by.ItemName or require("tr").word("Item")
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

-- What the open Workshop is crafting now (the CraftingButton's
-- ResearchName), or nil: Enter on a blueprint said nothing (VM, 2026-10-17).
function M.crafting_now()
    for _, m in ipairs(FindAllOf("WBP_Workshop_CraftModule_C") or {}) do
        if m:IsValid() and path_of(m):find("^/Engine/Transient%.") and screen.shown(m) then
            local ok, s = pcall(function() return plain(text_of(m.CraftingButton.ResearchName)) end)
            if ok and s and s ~= "" then return s end
        end
    end
    return nil
end

-- The Mess Hall's ration buttons (WBP_Button_SelectableServing): TitleText
-- and a rich ContentText "<ColorNegative>-40</>" that the plain label left
-- out, so both read "..., Morale" with no number (2026-10-14).
-- Its texts and the ration module's come from those widgets' own trees
-- (texts_under): searching every text in the game, under four class names
-- and twice for the ration in use, cost 58 ms per arrow and 490 ms on the
-- selected ration (timing log, Mess Hall, 2026-10-24).
function M.serving_label(path)
    if not (path and path:find("WBP_Button_SelectableServing_C_%d+$")) then return nil end
    local by = texts_under(path)
    if not by.TitleText then return nil end
    local label = by.TitleText
    if by.ContentText and by.ContentText ~= "" then
        label = label .. ", " .. require("tr").lower(by.TextBlock_106 or "Morale") .. " " .. by.ContentText
    end
    -- The window describes only the ration in use: say it with that one.
    -- Proven 2026-10-25: with focus on the other rations the module still
    -- shows the one in use (SelectedServingButton), so they have none.
    local b = StaticFindObject(path)
    -- Valid first: a null object's method can crash past pcall.
    local ok, sel = pcall(function() return b and b:IsValid() and b:GetSelected() end)
    if ok and sel then
        label = label .. ", selected"
        -- The ration module, one of the room window's own modules: said
        -- description first, then per crew, then for all crew. Premium
        -- rations show their cost instead of a description.
        local texts = {}
        local win = open_window()
        local function from_module(m)
            if m:GetClass():GetFName():ToString() ~= "WBP_MessHall_ServingSizeModule_C" then return end
            local mp = path_of(m)
            if not (mp and screen.shown(m)) then return end
            local mt = texts_under(mp)
            local names = {}
            for name in pairs(mt) do names[#names + 1] = name end
            table.sort(names)
            for _, name in ipairs(names) do
                local key = name:find("DescriptionText$") and 1 or (name == "FedCrewPerResourceText" and 2)
                    or (name == "RequiredResourceAmountForCrewText" and 3) or nil
                if key and not texts[key] and mt[name] ~= "" then texts[key] = mt[name] end
            end
        end
        -- USTVRoomManagementV2's module fields (as each_module below).
        for _, field in ipairs({ "PowerModules", "RoomInteractionModules", "CrewModules" }) do
            pcall(function()
                win[field]:ForEach(function(_, e)
                    local m = e:get()
                    if m and m:IsValid() then pcall(from_module, m) end
                end)
            end)
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
        -- Just the state (Casey, 2026-10-11): "Life Support on". From the
        -- room's own state, not the English label (firefly82's review,
        -- 2026-10-19); the label is the fallback.
        local ok, state = pcall(function() return require("ship").selected_state() end)
        local tr = require("tr")
        if ok and (state == "on" or state == "off") then label = tr.fill("{s} " .. state, room)
        elseif lower == "switch off" then label = tr.fill("{s} on", room)
        elseif lower == "switch on" then label = tr.fill("{s} off", room) end
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
            parts[#parts + 1] = "Not possible: " .. require("tr").lower(text)
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
                if ro and ro:IsValid() then skill = require("text").skill_icon_name(ro:GetFName():ToString()) or skill end
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
    if by.RankText then head = head .. ", " .. require("tr").lower(by.RankText) end
    if by.TraitText and by.TraitText ~= "" then head = head .. ", " .. by.TraitText end
    -- Injured or Severely Injured over the portrait, as in the away team
    -- list (awaymission.lua plaque_text, 2026-10-17).
    pcall(function()
        local st = plaque.HeroRoomText
        if st and st:IsValid() and screen.shown(st) then
            local s = plain(text_of(st))
            if s ~= "" and s:sub(1, 1) ~= "#" and s:lower():find("injur") then head = name .. ", " .. require("tr").lower(s) .. head:sub(#name + 1) end
        end
    end)
    parts[#parts + 1] = head
    local skills = M.skills_of(plaque.HeroStatSheet)
    if skills ~= "" then parts[#parts + 1] = skills end
    -- The bonus this hero gives the room ("+11% warp core repair rate.").
    for _, text in pairs(by) do
        if text:find("%%") then parts[#parts + 1] = (text:gsub("^%+", require("tr").word("Plus "))) end
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

-- Whether a room window is in front: the window's own state, IsActivated,
-- not whether it is on screen yet. It is activated from BP_OnActivated, while
-- still building unseen, and deactivated in the same call as its close
-- (probes 2026-10-22, roomwin.lua). Asked by being on screen, a room read
-- before it showed did not count, the view behind stayed "in front", and
-- Escape said no "Ship view". Not behind the System Map, as open_window.
-- A window whose state cannot be read counts by being on screen.
function M.window_open()
    local okm, map = pcall(function() return require("system").active() end)
    if okm and map then return false end
    for _, w in ipairs(FindAllOf("WBP_RoomManagementV2_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") then
            local ok, act = pcall(function() return w:IsActivated() end)
            if ok and type(act) == "boolean" then
                if act then return true end
            elseif screen.shown(w) then
                return true
            end
        end
    end
    return false
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
    -- A recruited ally (WBP_CombatAllyRecruitedButton) has only its upkeep,
    -- and Enter on it dismisses it: read "/, 30, UNIT 02, Maquis Raider
    -- Ally, combat power, Upkeep, 51, Dismiss Ally" (VM, 2026-10-17).
    local recruited = b:GetClass():GetFName():ToString() == "WBP_CombatAllyRecruitedButton_C"
    if recruited then
        for _, c in ipairs(recruit) do upkeep[#upkeep + 1] = c end
        recruit = {}
        parts[1] = "Recruited: " .. parts[1]
    end
    if #recruit > 0 then parts[#parts + 1] = "Recruitment: " .. table.concat(recruit, ", ") end
    if #upkeep > 0 then parts[#parts + 1] = "Upkeep: " .. table.concat(upkeep, ", ") .. " per cycle" end
    if recruited then
        local d = plain(text_of(b.DismissBtn_TXT))
        parts[#parts + 1] = "Enter: " .. (d ~= "" and d or "Dismiss ally")
    end
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
        if okh and hero then item = item .. ", " .. require("tr").word("hero") end
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
    local parts = { amount_of(plain(text_of(b.ResourceAmount)), icon_of(b.ResourceIcon) or require("tr").word("item")) }
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
    local item = amount_of(plain(text_of(lab.ResourceAmount)), icon_of(lab.ResourceIcon) or require("tr").word("item"))
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
    -- The hull below is the header's, shown on every screen: alone it is
    -- not this page. "Hull 220." was said after every reading in a German
    -- Engineering office, where the tab names match no reader and each
    -- reader is asked (firefly82's review, 2026-10-20).
    if #out == 0 then return nil end
    pcall(function()
        for _, h in ipairs(FindAllOf("WBP_HullIntegrity_C") or {}) do
            if h:IsValid() and screen.shown(h) then
                local cur, per = plain(text_of(h.CurrentHullValue)), plain(text_of(h.HullValuePerCycle))
                if cur:match("%d") then
                    out[#out + 1] = require("tr").fill("Hull {s}", cur) .. (per:match("%d") and (", " .. per .. " per cycle") or "")
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
local function tree_texts(root, skip)
    local out = {}
    local function walk(w, depth)
        if depth > 30 or not (w and w:IsValid()) or not screen.shown(w) then return end
        if skip and skip(w) then return end
        -- An ally's own button is read by the window's button list; walked
        -- here it came out as "51. Recruitment. 2. 30. /." (VM, 2026-10-17).
        local okc, cls = pcall(function() return w:GetClass():GetFName():ToString() end)
        if okc and (cls == "WBP_CombatAllyButton_C" or cls == "WBP_CombatAllyRecruitedButton_C") then return end
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
            -- With no allies the tab read "Currently no combat allies
            -- recruited" twice and the empty table's headings "Combat
            -- power. Upkeep." (Q Trial, VM, 2026-10-17): repeats are dropped,
            -- and the recruited table's headings when none are recruited.
            -- Each empty recruit slot shows its own NoAllyRecruited_TXT, so
            -- with one ally aboard the tab still said "Currently no combat
            -- allies recruited" (VM, 2026-10-17): with any recruited, those
            -- are left out and the count is said.
            local recruited = 0
            for _, b in ipairs(FindAllOf("WBP_CombatAllyRecruitedButton_C") or {}) do
                if b:IsValid() and path_of(b):find("^/Engine/Transient%.") and screen.shown(b) then recruited = recruited + 1 end
            end
            local texts = tree_texts(w, function(x)
                return recruited > 0 and x:GetFName():ToString():find("^NoAllyRecruited_TXT") ~= nil
            end)
            local any = recruited > 0
            if recruited > 0 then
                table.insert(texts, math.min(2, #texts + 1), recruited .. (recruited == 1 and " ally recruited" or " allies recruited"))
            end
            local HEADINGS = { ["combat power"] = true, upkeep = true }
            local parts, seen = {}, {}
            for _, s in ipairs(texts) do
                s = (s:gsub("%.%s*$", ""):gsub("^%l", string.upper))
                local key = s:lower()
                if not seen[key] and (any or not HEADINGS[key]) then
                    seen[key] = true
                    parts[#parts + 1] = s
                end
            end
            if #parts > 0 then
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
        if cond ~= "" and cond ~= "-" then item = item .. ", " .. require("tr").lower(cond) end
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
    if blocked ~= "" and not blocked:find("^#") then out[#out + 1] = "Not possible: " .. require("tr").lower(blocked) end
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

-- The page of the tab the player has just switched to, read once the game
-- has switched (switch_tab arms it; popups.lua calls M.tab_shown). Each
-- reader is asked and the one whose page is shown answers: by the game's
-- widgets, not the tab's name, so every language works alike (the English
-- name check before missed every other language; outside review,
-- 2026-10-17). Read after the fade, the page left behind no longer counts as
-- shown (it did just after leaving it; review, 2026-10-15).
-- Only until the next key: a window closed before its switch must not have
-- its next opening read as a tab switch.
local tab_read = nil   -- { window, before = focused path before the key, key }
function M.tab_shown(window)
    local r = tab_read
    if not (r and r.window == window) then return end
    tab_read = nil
    if require("keys").key_count ~= r.key then return end
    local t = nil
    for _, f in ipairs({ M.patients_text, M.trading_text, M.crew_text, M.biolab_text,
            M.workteams_text, M.allies_text }) do
        local okf, s = pcall(f)
        if okf and s then t = s break end
    end
    if t then require("speech").say(t, false) end
    -- Back on the Bridge's Combat Allies tab only "Combat Allies tab" was
    -- said: focus had stayed on the ally (see switch_tab).
    pcall(function()
        local f = require("focus")
        local label = f.current_label()
        if r.before and f.current_path() == r.before and label and label ~= "" then
            require("speech").say(label, false)
        end
    end)
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
    -- The window's own tab buttons (USTVRoomManagementV2: PowerTabButton,
    -- RoomInteractionTabButton, CrewTabButton; header dump), the shown ones;
    -- not a search of every button in the game for "TabButton" in its path,
    -- which also took Previous/NextTabButton (always shown, probe
    -- 2026-10-26), so a one-tab room never counted as one. ActiveTabButton
    -- is not a tab of its own: it points at the selected one (same probe),
    -- and counted, it made Stellar Cartography's one tab two.
    local tab_buttons = {}
    for _, f in ipairs({ "PowerTabButton", "RoomInteractionTabButton", "CrewTabButton" }) do
        local okb2, b = pcall(function() return w[f] end)
        if okb2 and b and b:IsValid() and screen.shown(b) then tab_buttons[#tab_buttons + 1] = b end
    end
    -- A window without those fields (an older build, such as the demo's,
    -- is not in the dump): the buttons under it named like a tab, without
    -- the arrows and ActiveTabButton.
    if #tab_buttons == 0 then
        local wp = path_of(w) .. "."
        print("[VoyagerAccess] rooms: no tab fields, tabs by name\n")
        for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
            local p = b:IsValid() and path_of(b)
            local n = p and p:match("([%w_]+)$") or ""
            if p and p:sub(1, #wp) == wp and n:find("TabButton", 1, true)
                and not n:find("^PreviousTabButton") and not n:find("^NextTabButton")
                and not n:find("^ActiveTabButton") and screen.shown(b) then
                tab_buttons[#tab_buttons + 1] = b
            end
        end
    end
    -- A window with one tab (Life Support): Left and Right said
    -- "Management tab" each time (firefly82, 2026-10-23). There is nothing
    -- to switch to, so the focused button is said again, as Up and Down do
    -- on a lone button (focus.lua say_if_alone).
    if #tab_buttons == 1 then
        local okl, label = pcall(function() return require("focus").current_label() end)
        if okl and label and label ~= "" then
            require("speech").say(label, true)
            return true
        end
    end
    M.tab_switched_at = os.clock()
    if dir < 0 then w:SelectPreviousTab() else w:SelectNextTab() end
    for _, b in ipairs(tab_buttons) do
        do
            local ok, sel = pcall(function() return b:GetSelected() end)
            if ok and sel then
                local name = plain(text_of(b.ButtonName))
                name = (name ~= "" and name or require("tr").word("Tab")):gsub("^%l", string.upper)
                require("speech").say(require("tr").fill("{s} tab", name), true)
                -- The page is read when the game has switched to it: the
                -- window's switcher event (OnActiveIndexChanged, on opening
                -- and on every Left and Right; probe 2026-10-22), once its
                -- fade is over (popups.lua, M.tab_shown). It replaces a
                -- read 300 ms after the key.
                local mine = { window = path_of(w), before = okb and before or nil, key = require("keys").key_count }
                tab_read = mine
                if not require("popups").room_tab_event() then
                    -- After the fade's usual length, as before the event.
                    print("[VoyagerAccess] rooms: tab event not hooked, page read in 300 ms\n")
                    ExecuteInGameThreadWithDelay(300, function() pcall(M.tab_shown, mine.window) end)
                else
                    -- The bounded fallback behind the event: none in 1.5 s
                    -- (the fade is about 0.4 s), and the page is read then.
                    ExecuteInGameThreadWithDelay(1500, function()
                        if tab_read ~= mine then return end
                        print("[VoyagerAccess] rooms: no tab event in 1.5 s, page read now\n")
                        pcall(M.tab_shown, mine.window)
                    end)
                end
                return true
            end
        end
    end
    return true
end

-- The room window's modules, from its own fields (USTVRoomManagementV2:
-- PowerModules, RoomInteractionModules, CrewModules), not by searching the
-- game: calls fn(module) for each valid one.
local MODULE_FIELDS = { "PowerModules", "RoomInteractionModules", "CrewModules" }
local function each_module(win, fn)
    for _, field in ipairs(MODULE_FIELDS) do
        pcall(function()
            win[field]:ForEach(function(_, e)
                local m = e:get()
                if m and m:IsValid() then fn(m) end
            end)
        end)
    end
end

-- True once the room window has built its modules. The window is activated
-- with none; they are made when the game calls OnLoadedModuleClasses, on
-- every opening (probe 2026-10-22). Until then the description and the
-- room's tab are missing ("Mess Hall, level 2, damaged."; VM, 2026-10-21),
-- so popups.lua waits for that event.
function M.modules_built(win)
    local n = 0
    each_module(win, function() n = n + 1 end)
    return n > 0
end

-- Read when a room window opens: name, level, state, and the description.
function M.window_text(path)
    -- Shown inside the window, not up to the screen: a room window opened a
    -- second time is read while it still fades in, and every text counted as
    -- hidden, so it was read as "Room." (demo, VM, 2026-10-21).
    local by = texts_under(path, StaticFindObject(path))
    local head = by.RoomNameText or require("tr").word("Room")
    if by.RoomLevel then head = head .. ", " .. by.RoomLevel:gsub("^lvl 0*", "level ") end
    if by.ActiveText and by.ActiveText ~= "" then head = head .. ", " .. require("tr").lower(by.ActiveText) end
    -- The energy it uses, a number beside a lightning icon in the header
    -- (not read until 2026-10-14, when power ran short).
    local energy = by.EnergyConsumptionText
    if energy and energy:match("^%d+$") then head = head .. ", uses " .. energy .. " energy" end
    local out = { head }
    -- The description module is one of the window's own modules (in
    -- PowerModules, the power tab; probe 2026-10-22), read only when that
    -- tab is shown: the Engineering Office opens on its work teams, and its
    -- description is not on screen then.
    local win = StaticFindObject(path)
    if win and win:IsValid() then
        each_module(win, function(w)
            if w:GetClass():GetFName():ToString() == "WBP_RoomDescriptionModule_C" and screen.shown(w, win) then
                local d = plain(text_of(w.DescriptionText))
                if d ~= "" then out[#out + 1] = d end
            end
        end)
    end
    -- Sickbay opens on Manage Patients.
    local okp, patients = pcall(M.patients_text)
    if okp and patients then out[#out + 1] = patients end
    -- Quarters open on Crew Info.
    local okc, crew = pcall(M.crew_text)
    if okc and crew then out[#out + 1] = crew end
    -- The tab can show a moment after the window: a working Sickbay with
    -- five patients said only "Sick bay, level 1, active, uses 7 energy"
    -- (VM, 2026-10-16). The window is read at the game's tab event now
    -- (popups.lua, since 2026-10-22); while the switcher still fades to the
    -- tab, its page is read once the fade is over (the game's
    -- IsTransitionPlaying, focus.after_switch), not 600 ms later.
    if not (okp and patients) and not (okc and crew) and win and win:IsValid() then
        pcall(function()
            local key = require("keys").key_count
            local function page()
                return M.patients_text() or M.crew_text() or M.biolab_text() or M.workteams_text() or M.allies_text()
            end
            -- On the next tick at the earliest: run now, the page was said
            -- before the window's header, which is said with interrupt
            -- after this returns (GPT review, 2026-10-26).
            ExecuteInGameThread(function() pcall(require("focus").after_switch, function() return StaticFindObject(path).WidgetSwitcher end, function()
                if require("keys").key_count ~= key then return end
                local t = page()
                if t then require("speech").say(t, false) return end
                -- The bounded fallback: a page not filled by the end of the
                -- fade is read once more 600 ms later, as before.
                ExecuteInGameThreadWithDelay(600, function()
                    pcall(function()
                        if require("keys").key_count ~= key then return end
                        local t2 = page()
                        if t2 then
                            print("[VoyagerAccess] rooms: page read 600 ms after the fade\n")
                            require("speech").say(t2, false)
                        end
                    end)
                end)
            end, "room page") end)
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
-- A button's shown texts by name (focus.lua: an analysis' name).
M.texts_under = texts_under

return M
