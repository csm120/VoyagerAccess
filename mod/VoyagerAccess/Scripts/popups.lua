-- Speaks windows that appear with text of their own: tutorials, toasts,
-- notifications, reports, mission info and detail views. Each listed class
-- is read once when it comes on screen, and again only after it has gone
-- away and come back. The list came from every widget class the game had
-- loaded in the first sector (316, 2026-10-10; docs/text-widgets.md).
-- Dialogue windows are dialogue.lua's job. Always-on HUD panels (quest
-- tracker, info panels) and mouse-hover tooltips are left out: they would
-- speak at every load or whenever the cursor rests on something.

local speech = require("speech")
local screen = require("screen")
local crumb = require("crumb")

local M = {}

local INTERVAL_MS = 300

local WATCH = {
    -- Tutorials
    -- The frame (title, Close) and, separately, the page with the body text:
    -- the pages are their own top-level widgets, not inside the frame.
    "WBP_TutorialInfoWidget_C",
    "WBP_TUT_CenterView_C", "WBP_TUT_CharacterView_C", "WBP_TUT_ColumnView_C",
    "WBP_CombatTutorial_C",
    "WBP_TutorialScreen1_C", "WBP_TutorialScreen2_C", "WBP_TutorialScreen3_C",
    "WBP_TutorialScreen4_C", "WBP_TutorialScreen5_C", "WBP_TutorialScreen6_C",
    "WBP_TutorialScreen7_C", "WBP_TutorialScreen8_C", "WBP_TutorialScreen9_C",
    "WBP_TutorialScreen10_C",
    -- Toasts and notifications
    "WBP_Toast_ChoiceHasImpact_C", "WBP_Toast_Error_C", "WBP_Toast_Receive_C",
    "WBP_Toast_Warning_C", "WBP_SingleNotification_Default_C",
    "WBP_SingleNotification_Error_C",
    -- Reports and info windows
    "WBP_CrewLossInfoWidget_C", "WBP_EnergyLossInfoWidget_C", "WBP_ResearchReport_C",
    "WBP_MissionInfoWidget_C", "WBP_CommonInfoWidget_C", "WBP_CommonInfoWidget_MissionInfo_C",
    "WBP_ResearchInfoWidget_C", "WBP_ConstructionInfoWidget_C",
    "WBP_ConstructionActionReportWidget_C", "WBP_ConstructionActionErrorInfo_C",
    "WBP_SideMissionFinished_C", "WBP_EndOfGameMissionInfo_01_C",
    "WBP_EmergencyFoodActivationInfo_C", "WBP_AM_ConfirmStart_C", "WBP_RoomPrompt_C",
    "WBP_LogEventWidget_C",
    -- A point of interest's event: title and description (events.lua reads
    -- the options)
    "WBP_POIMultipleChoice_C",
    -- A room's window: name, level, state, description (rooms.lua reads
    -- each button with its costs)
    "WBP_RoomManagementV2_C",
    -- Detail views (a selected place, ship, story or event)
    "WBP_POIDetailView_C", "WBP_PlanetDetailView_C", "WBP_ShipDetailView_C",
    "WBP_StoryDetailView_C", "WBP_ResourceEventDetailView_C",
    "WBP_GenericLocationDetailView_C", "WBP_AwayMissionDetailView_C",
    "WBP_AwayMissionEventView_C", "WBP_PoiEventWidget_C",
    -- Away team selection: the mission, heroes needed, recommendations and
    -- challenges (awaymission.lua reads the slots and heroes)
    "WBP_AwayMissionLoadout_C",
    -- An away mission's end: MISSION COMPLETE, challenges, experience,
    -- rewards (inside the mission window's DialogueConsequences)
    "WBP_AwayMissionOutcome_C",
    -- The Overview (Warp Core, Morale, Crew, Heroes, Combat tabs; reached
    -- with N); read again when its tab changes
    "WBP_OverviewInfoWidget_C",
    -- Its combat counterpart, found by scanning for like screens; not yet
    -- seen, so read as plain text until a battle shows its layout
    "WBP_BattleResultLCARS_C",
    -- First launch only: Performance Selection, then Gamma
    "WBP_FirstPerformanceSelection_C", "WBP_GammaCorrection_C",
}

-- Text widget classes, listed separately in case FindAllOf does not
-- return subclasses. Never add EditableText or EditableTextBox: GetText on
-- one whose Slate widget is not built crashes the game inside
-- FSlateEditableTextLayout::GetText (2026-10-10 22:46).
local TEXT_CLASSES = { "TextBlock", "CommonTextBlock", "RichTextBlock",
    "CommonRichTextBlock", "WBP_TypeWriterRichTextBlock_C" }

-- Button and frame labels that only add noise when read with a window.
local NOISE = { CLOSE = true, TUTORIAL = true }

local announced = {}   -- path -> true while it stays on screen

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

-- Markup off, brackets off ("[Stellar Cartography]"), "???" read as
-- "unknown", and a lone symbol ("+", an icon's label) dropped. Heard
-- 2026-10-10: "+. ???. Deuterium. ... Upgrade [Stellar Cartography]".
local function plain(s)
    s = s:gsub("<[^>]*>", ""):gsub("%[([^%]]*)%]", "%1"):gsub("%?%?%?", "unknown")
    -- Text escapes the game leaves in ("Duranium &amp; Tritanium", 2026-10-11).
    s = s:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", "\""):gsub("&#39;", "'")
    s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if not s:find("%w") then return "" end
    return s
end

-- On-screen texts inside the widget at path, in creation order, as
-- { name = last part of the text widget's name, text = plain text }.
local function parts_under(path)
    local prefix = path .. "."
    local parts, seen_obj = {}, {}
    for _, cls in ipairs(TEXT_CLASSES) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            if t:IsValid() then
                local tp = path_of(t)
                if tp and not seen_obj[tp] and tp:sub(1, #prefix) == prefix and screen.shown(t) then
                    seen_obj[tp] = true
                    local ok, s = pcall(function() return t:GetText():ToString() end)
                    s = ok and plain(s) or ""
                    if s ~= "" and s:sub(1, 1) ~= "#" and not NOISE[s:upper()] then
                        parts[#parts + 1] = { name = tp:match("([^%.]+)$"), text = s }
                    end
                end
            end
        end
    end
    return parts
end

-- A selected point of interest's detail window. Its texts come out of the
-- game in creation order ("unknown. Deuterium. Resources. 7,104.0. System.
-- Ship Wreck. Upgrade ..."), so they are put in reading order by name
-- (names read 2026-10-10): "Ship Wreck, System 7,104.0. Resources:
-- Deuterium, amount unknown. Upgrade ...". Unnamed extras go last.
local function poi_detail(parts)
    local by = {}
    for _, p in ipairs(parts) do
        if not by[p.name] then by[p.name] = p.text end
    end
    -- "Upgrade Stellar Cartography to collect more data." explains a hidden
    -- amount, so it is folded into it: "amount unknown until Stellar
    -- Cartography is upgraded" (Casey chose this wording, 2026-10-10).
    local upgrade = by.UpgradeText and by.UpgradeText:match("^Upgrade (.-) to collect more data")
    local until_text = upgrade and (" until " .. upgrade .. " is upgraded") or ""
    local rewards, pending = {}, nil
    for _, p in ipairs(parts) do
        if p.name == "ResourceAmountTextBlock" then
            pending = p.text
        elseif p.name == "ResourceNameTextBlock" then
            local amount = pending and (pending == "unknown" and (", amount unknown" .. until_text)
                or (", amount " .. pending)) or ""
            rewards[#rewards + 1] = p.text .. amount
            pending = nil
        end
    end
    local out = {}
    local place = by.LocationNameTextBlock
    if place then
        -- The system is named by a number such as "7,104.0"; the ".0" adds nothing.
        -- It is a name, so it is said the way a Starfleet officer would:
        -- digit by digit with zero as "oh", "7 1 oh 4" (Casey, 2026-10-11).
        local system = by.SystemNameTextBlock and by.SystemNameTextBlock:gsub("%.0$", ""):gsub(",", "")
            :gsub("%d", "%0 "):gsub("0 ", "oh "):gsub(" $", "")
        if system then place = place .. ", in system " .. system end
        out[#out + 1] = place
    end
    if #rewards > 0 then
        out[#out + 1] = (by.ResourceEventNameTextBlock or "Resources") .. ": " .. table.concat(rewards, "; ")
    end
    if by.UpgradeText and not upgrade then out[#out + 1] = by.UpgradeText end
    -- Anything else the window shows, after the known parts.
    local known = { LocationNameTextBlock = true, SystemNameTextBlock = true, System_TextBLock = true,
        ResourceEventNameTextBlock = true, UpgradeText = true }
    for _, p in ipairs(parts) do
        -- A stray "System" label is left over once the system is named.
        if not known[p.name] and not p.name:find("^Resource") and p.text ~= "System" then out[#out + 1] = p.text end
    end
    return table.concat(out, ". ")
end

-- A point-of-interest event: title and description only; its options are
-- read one at a time as focus moves (events.lua).
-- The resources named by the reward icons under path, in order
-- ("MI_UI_Duranium_WhiteNoBG" -> Duranium).
local function reward_resources(path)
    local out = {}
    for _, r in ipairs(FindAllOf("WBP_PoIMultipleChoice_Reward_C") or {}) do
        local rp = r:IsValid() and path_of(r)
        if rp and rp:sub(1, #path + 1) == path .. "." and screen.shown(r) then
            local ok, icon = pcall(function() return r.Reward_Image.Brush.ResourceObject:GetFName():ToString() end)
            out[#out + 1] = ok and icon:match("^MI_UI_(%a+)") or "resources"
        end
    end
    return out
end

-- After an option is picked the same window shows the result (read
-- 2026-10-11): ResultOutcome_Text "Good", then reward amounts each followed
-- by a distribution line ("65% reward distribution.", "in total stored.").
local function poi_result(parts, by, path)
    local out = {}
    if by.Header_Text then out[#out + 1] = by.Header_Text end
    if by.PoI_Description_RichText then out[#out + 1] = by.PoI_Description_RichText end
    out[#out + 1] = "Outcome: " .. by.ResultOutcome_Text:lower()
    -- Both amounts come before both distribution lines, so pair by position.
    local names = reward_resources(path)
    local amounts, lines = {}, {}
    for _, p in ipairs(parts) do
        if p.name == "RewardAmount_Text" then amounts[#amounts + 1] = (p.text:gsub("^%+", ""))
        elseif p.name == "RewardDistribution_Text" then lines[#lines + 1] = p.text end
    end
    for i, line in ipairs(lines) do
        local amount = amounts[i] or ""
        local res = names[i] or names[1] or ""
        local pct = line:match("(%d+)%% reward distribution")
        if pct then
            out[#out + 1] = amount .. " " .. res .. ", " .. pct .. "% of the maximum"
        elseif line:find("in total stored", 1, true) then
            out[#out + 1] = amount .. " " .. res .. " stored in total"
        else
            out[#out + 1] = amount .. " " .. res .. ", " .. line
        end
    end
    for k, s in ipairs(out) do out[k] = s:gsub("%.%s*$", ""):gsub("%s+,", ","):gsub("  +", " ") end
    return table.concat(out, ". ") .. "."
end

local function poi_event(parts, path)
    local by = {}
    for _, p in ipairs(parts) do
        if not by[p.name] then by[p.name] = p.text end
    end
    if by.ResultOutcome_Text then return poi_result(parts, by, path) end
    local out = {}
    if by.Header_Text then out[#out + 1] = by.Header_Text end
    if by.PoI_Description_RichText then out[#out + 1] = by.PoI_Description_RichText end
    -- Locked options take no focus, so they are read here (2026-10-11).
    local locked = require("events").locked_summary()
    if locked ~= "" then out[#out + 1] = locked end
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- The Construction Report (WBP_ConstructionInfoWidget, read 2026-10-11),
-- which comes up when building, repair or dismantling finishes. Its parts
-- came out in storage order ("ENTER SHIP to manage manually. 18. 36. Total
-- costs after activation. Dismantled. Repaired. Built."). Each room is a
-- WBP_ConstructionActionReportWidget in a section box named Dismantled,
-- Repaired or Built (its parent's name); those are read here, not alone.
local function shown_widget(cls)
    for _, w in ipairs(FindAllOf(cls) or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then return w end
    end
    return nil
end

local function text_of_widget(w)
    if not (w and w:IsValid() and screen.shown(w)) then return "" end
    local ok, s = pcall(function() return w:GetText():ToString() end)
    return ok and plain(s) or ""
end

local function construction_report(parts)
    local by = {}
    for _, p in ipairs(parts) do if not by[p.name] then by[p.name] = p.text end end
    local out = { by.HeaderTextBlock or "Construction Report" }
    local sections, order = {}, { "Dismantled", "Repaired", "Built" }
    for _, w in ipairs(FindAllOf("WBP_ConstructionActionReportWidget_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
            local parent = w:GetParent()
            local section = parent and parent:IsValid() and parent:GetFName():ToString() or "Other"
            local entry = { text_of_widget(w.RoomName) }
            local level = text_of_widget(w.RoomLevel)
            if level ~= "" then entry[#entry + 1] = level:lower() end
            local ls = text_of_widget(w.LifeSupport)
            if ls ~= "" then entry[#entry + 1] = ls:lower() end
            local crew = text_of_widget(w.CrewValueNew)
            if crew ~= "" then entry[#entry + 1] = "crew " .. crew end
            local energy = text_of_widget(w.EnergyValueNew)
            if energy ~= "" then entry[#entry + 1] = "energy " .. energy end
            sections[section] = sections[section] or {}
            table.insert(sections[section], table.concat(entry, ", "))
        end
    end
    for _, name in ipairs(order) do
        if sections[name] then out[#out + 1] = name .. ": " .. table.concat(sections[name], "; ") end
    end
    local totals = {}
    if by.CrewValue then totals[#totals + 1] = "crew " .. by.CrewValue end
    if by.EnergyValue then totals[#totals + 1] = "energy " .. by.EnergyValue end
    if #totals > 0 then
        out[#out + 1] = (by.NewUsage or "Total costs after activation") .. ": " .. table.concat(totals, ", ")
    end
    out[#out + 1] = "Close finishes all actions, activates the rooms and collects resources; "
        .. "Enter Ship lets you manage it yourself"
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- Texts of a window in screen order: a walk of its widget tree, which is
-- the order they are laid out in (FindAllOf gives creation order, which
-- came out jumbled more than once). Hidden widgets and buttons' own labels
-- are left out; skip(name, text) returns true to drop a text, or a string
-- to say instead.
local function ordered_texts(root, skip)
    local W = StaticFindObject("/Script/UMG.UserWidget")
    local PANEL = StaticFindObject("/Script/UMG.PanelWidget")
    local BTN = StaticFindObject("/Script/CommonUI.CommonButtonBase")
    local out = {}
    local function walk(w, depth)
        if depth > 40 or not (w and w:IsValid()) or not screen.shown(w) then return end
        if w:IsA(BTN) then return end
        local ok, txt = pcall(function() return w:GetText():ToString() end)
        if ok and type(txt) == "string" then
            local t = plain(txt)
            local name = w:GetFName():ToString()
            if t ~= "" and skip then
                local keep = skip(name, t)
                if type(keep) == "string" then t = keep elseif keep then t = "" end
            end
            if t ~= "" then out[#out + 1] = t end
            return
        end
        if w:IsA(W) then
            local tree = w.WidgetTree
            if tree and tree:IsValid() and tree.RootWidget then walk(tree.RootWidget, depth + 1) end
        elseif w:IsA(PANEL) then
            for i = 0, w:GetChildrenCount() - 1 do walk(w:GetChildAt(i), depth + 1) end
        end
    end
    walk(root, 0)
    return out
end

-- Joins texts into sentences, putting numbers with the label before them:
-- "Available Energy", "78", "120" -> "Available Energy 78 of 120".
local function join_numbers(texts)
    local out, run = {}, 0
    for _, t in ipairs(texts) do
        local number = t:match("^[%+%-]?[%d,%.]+%%?$") or t:match("^%(?[%d,]+ %- [%d,]+%)?$")
        if number and #out > 0 then
            run = run + 1
            out[#out] = out[#out] .. (run == 2 and " of " or " ") .. t
        else
            run = 0
            out[#out + 1] = t
        end
    end
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- The Overview (WBP_OverviewInfoWidget, read 2026-10-11): its tab bar,
-- then the selected tab's content. Left and Right switch tabs (focus.lua).
local OVERVIEW_SKIP = { ScreenName_Text = true, CommonTextBlock_30 = true, CommonTextBlock_18 = true }
-- Numbers that have no label of their own on screen (the label is an icon
-- or a position), said with one.
local OVERVIEW_LABELS = {
    ConsumedDeuteriumText = "The warp core uses %s deuterium per cycle",
    ProducedEnergyText = "and produces %s energy",
    CyclesText = "%s before forced gray mode",
    SmallBatteriesAmount = "Small batteries: %s",
    LargeBatterieAmount = "Large batteries: %s",
    -- Morale tab: each row is an amount, a condition and its effect.
    ConditionAmount = "%s crew", ConditionAmountSevere = "%s crew",
    ConditionMaxMoraleDeduction = "max morale %s", SevereConditionMaxMoraleDeduction = "max morale %s",
    TotalMaxMoraleDeductionAmount = "Total max morale change %s",
    Happiness_Text = "Total %s per cycle",
    current_morale = "Current morale %s",
}
-- Said by name only, no number: "Max Morale" after every row.
local OVERVIEW_DROP = { Morale = true, Morale1 = true }

local function overview(_, path)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return "" end
    local tab = nil
    for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
        local p = b:IsValid() and path_of(b)
        if p and p:sub(1, #path + 1) == path .. "." and p:find("_Tab_Button$") and screen.shown(b) then
            local ok, sel = pcall(function() return b:GetSelected() end)
            if ok and sel then
                local okt, t = pcall(function() return b.Button_Text:GetText():ToString() end)
                tab = okt and t or nil
            end
        end
    end
    local level = nil   -- Heroes tab: "Lv. 1" comes before the name it belongs to
    local texts = ordered_texts(w, function(name, t)
        if OVERVIEW_LABELS[name] then
            return string.format(OVERVIEW_LABELS[name], (t:gsub("^%+", ""):gsub("/$", "")))
        end
        if name == "LevelText" then
            level = t:gsub("^Lv%.%s*", "level ")
            return true
        end
        if name == "HeroName" and level then
            local said = t .. ", " .. level
            level = nil
            return said
        end
        return OVERVIEW_SKIP[name] or OVERVIEW_DROP[name] or t == "?" or t == "Undiscovered" or t == ")" or t == "!"
            or name:find("^Upgrade") or name:find("^AddedValue") or name == "SkillValue"
    end)
    table.insert(texts, 1, "Overview, " .. (tab or "") .. " tab")
    return join_numbers(texts)
end

M.ordered_texts = ordered_texts

-- Tutorials describe the mouse and what is seen ("Open the OVERVIEW
-- screen"). After a tutorial's page the mod says its own keys for the same
-- thing (Casey, 2026-10-11). Keyed by the tutorial's title.
local TUTORIAL_KEYS = {
    ["Activate Room"] = "in the ship view, choose the room with the arrows, press Enter, then Enter on its power button",
    ["Away Mission"] = "Up and Down walk the choices, their heroes and Confirm. Enter on a hero selects them; Enter on Confirm confirms",
    ["Away Mission - Advanced"] = "Up and Down walk the choices, their heroes and Confirm. Enter on a hero selects them; Enter on Confirm confirms",
    ["Basic Resources"] = "C reads your resources",
    ["Consequences"] = "Up and Down move between the options, and each says its outcome odds; Enter picks one",
    ["Engineering Office"] = "choose the Engineering Office in the ship view and press Enter to open it",
    ["Help"] = "F1 lists the keys for the screen you are on, and L says where you are",
    ["Life support"] = "rooms say on or off as you move through the decks; open Life support with Enter and press Enter on its power button",
    ["Morale"] = "press N, choose Overview, then press Right to reach the Morale tab",
    ["Points of Interest"] = "V switches to the System Map; Up and Down move through the points, nearest first, and Enter opens Scan and Set course",
    ["Repairing Rooms"] = "choose the damaged room in the ship view, press Enter, then Enter on Repair",
    ["Scan"] = "on the System Map, choose a point with Up and Down, press Enter, then Enter on Scan",
    ["System Map Navigation"] = "V switches between the ship and the System Map; on the map, Up and Down move through the points and Enter opens Scan and Set course",
    ["Transporter Room"] = "on the away team screen, Up and Down move between the slots and Enter chooses a hero",
    ["Warp Core"] = "open Main Engineering with Enter, press Right to reach the Warp Core tab, then Up and Down choose the tier",
    ["Fatigue"] = "a hero's fatigue is said in away mission results; N, Overview, then the Heroes tab lists your heroes",
}

local function tutorial_title()
    for _, w in ipairs(FindAllOf("WBP_TutorialInfoWidget_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
            for _, p in ipairs(parts_under(path_of(w))) do
                local t = p.text:match("^Tutorial: (.+)$")
                if t then return t end
                if TUTORIAL_KEYS[p.text] then return p.text end
            end
        end
    end
    return nil
end

local function tutorial_page(parts)
    local out = {}
    for _, p in ipairs(parts) do out[#out + 1] = p.text end
    local text = table.concat(out, ". ")
    local title = tutorial_title()
    local keys = title and TUTORIAL_KEYS[title]
    if keys then text = text .. ". With Voyager Access: " .. keys .. "." end
    return text
end

local LAYOUTS = { WBP_POIDetailView_C = poi_detail, WBP_POIMultipleChoice_C = poi_event,
    WBP_TUT_CenterView_C = tutorial_page, WBP_TUT_CharacterView_C = tutorial_page,
    WBP_TUT_ColumnView_C = tutorial_page,
    WBP_OverviewInfoWidget_C = overview,
    WBP_ConstructionInfoWidget_C = construction_report,
    -- Read with the report above; alone it would come out unlabeled.
    WBP_ConstructionActionReportWidget_C = function(parts)
        if shown_widget("WBP_ConstructionInfoWidget_C") then return "" end
        local out = {}
        for _, p in ipairs(parts) do out[#out + 1] = p.text end
        return table.concat(out, ". ")
    end,
    WBP_RoomManagementV2_C = function(_, path) return require("rooms").window_text(path) end,
    WBP_AwayMissionLoadout_C = function() return require("awaymission").window_text() end,
    WBP_AwayMissionOutcome_C = function(_, path) return require("awaymission").outcome_text(path) end }

-- All on-screen text inside the widget at path, in reading order.
function M.text_under(path)
    local parts = parts_under(path)
    -- The class, not the name: inside the HUD the window is just named
    -- "POIDetailView".
    local w = StaticFindObject(path)
    local cls = (w and w:IsValid()) and w:GetClass():GetFName():ToString() or nil
    if cls and LAYOUTS[cls] then return LAYOUTS[cls](parts, path) end
    local out, seen = {}, {}
    for _, p in ipairs(parts) do
        if not seen[p.text] then
            seen[p.text] = true
            out[#out + 1] = p.text
        end
    end
    return table.concat(out, ". ")
end

-- Watched widgets on screen now, outermost first, nested ones dropped.
local function on_screen()
    local found, order = {}, {}
    for i, cls in ipairs(WATCH) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            if w:IsValid() then
                local p = path_of(w)
                if p and p:find("^/Engine/Transient%.") and screen.shown(w) then
                    found[#found + 1] = p
                    order[p] = i
                end
            end
        end
    end
    table.sort(found, function(a, b) return #a < #b end)
    local outer = {}
    for _, p in ipairs(found) do
        local nested = false
        for _, o in ipairs(outer) do
            if p:sub(1, #o + 1) == o .. "." then nested = true break end
        end
        if not nested then outer[#outer + 1] = p end
    end
    -- Speak in list order: a tutorial's title before its page.
    table.sort(outer, function(a, b) return order[a] < order[b] end)
    return outer
end

-- The watched windows on screen now (focus.lua focuses one that opens
-- with nothing focused).
M.open_windows = on_screen

-- Dry run for development: what would be spoken now, without speaking.
function M.preview()
    local lines = {}
    for _, p in ipairs(on_screen()) do
        lines[#lines + 1] = p:match("([%w_]+)$") .. ": " .. M.text_under(p)
    end
    return table.concat(lines, " || ")
end

-- A tutorial opens with keyboard focus on an unlabeled helper button, and
-- Tab and the arrows do not leave it (Casey was stuck twice, 2026-10-10).
-- SetFocus on its Close button did not move focus, so Enter closes an open
-- tutorial directly instead (focus.lua calls this first). Clicking Close
-- this way is proven (it opened the next tutorial, 2026-10-10).
function M.close_tutorial()
    for _, w in ipairs(FindAllOf("WBP_TutorialInfoWidget_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
            local close = w.CloseButton
            if close and close:IsValid() then
                print("[VoyagerAccess] tutorial: close\n")
                close:HandleButtonPressed()
                close:HandleButtonReleased()
                close:HandleButtonClicked()
                return true
            end
        end
    end
    return false
end

-- Windows already read are kept in a file, so reloading the mod during
-- development does not read the open windows to Casey again.
local SEEN_PATH = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\windows-read.txt"

local function save_announced()
    local f = io.open(SEEN_PATH, "w")
    if not f then return end
    for p in pairs(announced) do f:write(p, "\n") end
    f:close()
end

local function load_announced()
    local f = io.open(SEEN_PATH, "r")
    if not f then return end
    for line in f:lines() do announced[line] = true end
    f:close()
end

local last_text = {}   -- path -> text last read, for windows read again on change

local function poll()
    crumb.at("popups: scan")
    local now, spoken = {}, {}
    for _, p in ipairs(on_screen()) do
        now[p] = true
        -- Tutorials only explain; Casey asked for them to close by
        -- themselves (2026-10-10). Close one poll after it was read, so its
        -- page (a separate widget) has been read too. R repeats the text.
        if announced[p] and p:find("WBP_TutorialInfoWidget_C", 1, true) then
            M.close_tutorial()
        end
        -- An event window changes in place (options, then the result), so
        -- it is read again whenever its text changes (2026-10-11).
        local reread = announced[p] and (p:find("WBP_POIMultipleChoice_C", 1, true)
            or p:find("WBP_OverviewInfoWidget_C", 1, true))
        if not announced[p] or reread then
            crumb.at("popups: read " .. p)
            local text = M.text_under(p)
            -- A window with no words, only a number, said just "1" when the
            -- System Map opened (2026-10-11); it is skipped.
            if text:find("%a") and text ~= last_text[p] and not (reread and last_text[p] == nil) then
                print("[VoyagerAccess] popup: " .. text .. " (" .. (p:match("([%w_]+)$") or "?") .. ")\n")
                speech.say_long(text)
                spoken[#spoken + 1] = text
            end
            last_text[p] = text
        end
    end
    local changed = false
    for p in pairs(now) do if not announced[p] then changed = true end end
    for p in pairs(announced) do if not now[p] then changed = true end end
    announced = now
    if changed then save_announced() end
    if #spoken > 0 then require("dialogue").remember(table.concat(spoken, ". ")) end
end

function M.install()
    load_announced()
    LoopInGameThreadWithDelay(INTERVAL_MS, function()
        local ok2, err = pcall(poll)
        if not ok2 then print("[VoyagerAccess] popups error: " .. tostring(err) .. "\n") end
    end)
end

return M
