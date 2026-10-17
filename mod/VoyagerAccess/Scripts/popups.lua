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
    -- "Cannot save now" (RichText), checked in the VM 2026-10-15 from the
    -- coverage list. Not WBP_Toast_Quip: every one of Q's 45 quips has a
    -- voice clip (SXW_VO_*Quip*, asset list, 2026-10-15).
    "WBP_Toast_SaveBlocked_Error_C",
    -- Reports and info windows
    "WBP_CrewLossInfoWidget_C", "WBP_EnergyLossInfoWidget_C",
    "WBP_MissionInfoWidget_C", "WBP_CommonInfoWidget_C", "WBP_CommonInfoWidget_MissionInfo_C",
    -- The report's title, then its rewards (they came first, 2026-10-14)
    "WBP_ResearchInfoWidget_C", "WBP_ResearchReport_C", "WBP_ConstructionInfoWidget_C",
    "WBP_ConstructionActionReportWidget_C", "WBP_ConstructionActionErrorInfo_C",
    "WBP_SideMissionFinished_C", "WBP_EndOfGameMissionInfo_01_C",
    "WBP_EmergencyFoodActivationInfo_C", "WBP_AM_ConfirmStart_C", "WBP_RoomPrompt_C",
    "WBP_LogEventWidget_C", "WBP_LogEventWidget_Multitab_C",
    -- A side mission offer ("Pursuit of Happiness", Neelix, 2026-10-14):
    -- title, speaker, request and time limit; its options are
    -- WBP_MultipleChoice_Button widgets, read as the window's button list.
    "WBP_MultipleChoiceWidget_C",
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
    -- The loading screen: a new campaign opens on "You are the Captain of
    -- the Federation starship U.S.S. Voyager..." (full game, 2026-10-14)
    "WBP_Loading_Screen_C",
    -- The away team's start confirmation (WARNING, unassigned slots)
    "WBP_AM_ConfirmStart_C",
    -- The pause menu's confirmations ("Exit to Main Menu. Are you sure? You
    -- will lose all progress..."): silent, with nothing focused (2026-10-14)
    "WBP_PauseMenu_Confirms_C",
    -- The main menu's Delete Profile warning, its own class (2026-10-15)
    "WBP_DeleteProfileWarning_C",
    -- "Display Settings. Display settings have been changed. Do you want to
    -- save and apply them?" with REJECT and ACCEPT, after a resolution
    -- change (created in the VM, 2026-10-15; the VM has one resolution only)
    "WBP_ConfirmUserSettingDisplay_C",
    -- From the coverage list (every widget in the game, 2026-10-15), each
    -- created in the VM to check its parts: Game Over (Return to Main Menu,
    -- Reload Save), No Way Back before the endgame (YES, NO), the Crafting
    -- Report, the generic Yes/No confirmation and Hero Lost.
    "WBP_GameOver_C", "WBP_NoWayBackWidget_C", "WBP_CraftingResult_C", "WBP_ConfirmationWidget_C",
    "WBP_HeroUnavailableWidget_C", "WBP_SectorExitEventWidget_C", "WBP_CombatAutoResolve_C",
    -- Q Trials setup: its first page is a warning ("Q Trials is designed
    -- for experienced Captains..."), ABORT and ACCEPT (2026-10-14)
    "WBP_Sandbox_Setup_C",
    -- A ship room's action ring: its centre says what the room is
    -- (2026-10-14; focus.lua names the segments)
    "WBP_RadialMenu_C",
    -- Leave Sector: choose the next sector (first met in a Q Trial, VM,
    -- 2026-10-14); its entries are read by M.leave_sector_entry
    "WBP_LeaveSector_C",
    -- Q Trials results (sector end or game over): sandbox_result
    "WBP_SandboxSectorResult_C",
    -- Room warnings found by the asset scan and opened in the VM
    -- (2026-10-16): removing a work team that is busy on a room, and a
    -- Cargo Bay change that would lose stock ("500 Deuterium").
    "WBP_EngineeringOffice_Confirmation_C", "WBP_CargoSwap_Confirmation_C",
}
M.ROOM_WARNINGS = { "WBP_EngineeringOffice_Confirmation_C", "WBP_CargoSwap_Confirmation_C" }

-- The save window's warnings, laid out like the Delete Profile warning
-- (heading, ReportContent, BACK and ACCEPT). Restart Sector's "Overwrite
-- Savegame" was silent and focus stayed on the menu behind it (VM,
-- 2026-10-15); the others are from the coverage list.
local SAVE_WARNINGS = { "WBP_OverrideSavegameInfoWidget_C", "WBP_OldSavegameInfoWidget_C",
    "WBP_SavegameInfoWidget_Dependency_Hard_C", "WBP_SavegameInfoWidget_Dependency_Soft_C",
    "WBP_SavegameInfoWidget_Dependency_Sandbox_C" }
M.SAVE_WARNINGS = SAVE_WARNINGS
for _, c in ipairs(SAVE_WARNINGS) do WATCH[#WATCH + 1] = c end
local function is_save_warning(p)
    for _, c in ipairs(SAVE_WARNINGS) do if p:find(c, 1, true) then return true end end
    return false
end

-- Text widget classes, listed separately in case FindAllOf does not
-- return subclasses. Never add EditableText or EditableTextBox: GetText on
-- one whose Slate widget is not built crashes the game inside
-- FSlateEditableTextLayout::GetText (2026-10-10 22:46).
local TEXT_CLASSES = { "TextBlock", "CommonTextBlock", "RichTextBlock",
    "CommonRichTextBlock", "WBP_TypeWriterRichTextBlock_C" }

-- Button and frame labels that only add noise when read with a window.
-- Button labels: they are in the button list, and in a window's text they
-- only interrupt it ("Mess Hall. ENTER SHIP. Out of Deuterium", 2026-10-14).
local NOISE = { CLOSE = true, TUTORIAL = true, ["ENTER SHIP"] = true }

local announced = {}   -- path -> true while it stays on screen
local last_text = {}   -- path -> text last read, for windows read again on change

-- True once the window at path has been read (focus.lua's window list).
-- For a few seconds, read the windows whose path contains needle again when
-- their text changes. A second scan reuses the open POIDetailView, so the
-- new planet's event and its item rewards were never read, only the rewards
-- as buttons (Casey, "Kazon Security Codes", 2026-10-14). system.lua calls
-- this on Scan.
local reread_until = {}   -- needle -> os.time() until which it is re-read
function M.reread_for(needle, seconds)
    reread_until[needle] = os.time() + (seconds or 4)
end
local function rereading(p)
    for needle, t in pairs(reread_until) do
        if os.time() <= t and p:find(needle, 1, true) then return true end
    end
    return false
end

function M.was_announced(path)
    return announced[path] == true
end

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

-- Markup off, brackets off ("[Stellar Cartography]"), "???" read as
-- "unknown", and a lone symbol ("+", an icon's label) dropped. Heard
-- 2026-10-10: "+. ???. Deuterium. ... Upgrade [Stellar Cartography]".
local function plain(s)
    s = require("text").prep(s)  -- icons beside numbers, list line breaks (text.lua)
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
                    -- By the button it sits in too: the German tutorial read
                    -- "Tutorial: Erschöpfung. SCHLIESSEN" (VM, 2026-10-16).
                    local in_close = tp:find("%.Close[%w_]*Button[%w_]*%.") or tp:find("%.EnterShip[%w_]*%.")
                    if s ~= "" and s:sub(1, 1) ~= "#" and not NOISE[s:upper()] and not in_close then
                        parts[#parts + 1] = { name = tp:match("([^%.]+)$"), text = s, path = tp }
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
    local exit = M.sector_exit_detail(parts)
    if exit then return exit end
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
        -- The full game adds a name after the number ("112.0 Vidiian System"),
        -- which came out "1 1 2 .oh  Vidiian System" (2026-10-14): only the
        -- number is said digit by digit, then the name.
        local raw = by.SystemNameTextBlock
        local system = raw and require("system").spoken_number(raw)
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
    local extras = {}
    for _, p in ipairs(parts) do
        -- A stray "System" label is left over once the system is named.
        if not known[p.name] and not p.name:find("^Resource") and p.text ~= "System" then
            out[#out + 1] = p.text
            if not p.text:find("%-Zone$") and not p.text:find("NO DATA") and not p.text:find("^Scan ") then
                extras[#extras + 1] = p.text
            end
        end
    end
    -- What the point holds, for the System Map list: the full game's event
    -- ids ("S1RE8") do not name the resource, so every scanned point read
    -- just "scanned" (Q Trial, VM, 2026-10-15).
    local names = {}
    if by.ResourceEventNameTextBlock and by.ResourceEventNameTextBlock ~= "Resources" then
        names[#names + 1] = by.ResourceEventNameTextBlock
    end
    for _, p in ipairs(parts) do
        if p.name == "ResourceNameTextBlock" then names[#names + 1] = p.text end
    end
    for _, e in ipairs(extras) do names[#names + 1] = e end
    if #names > 0 then pcall(function() require("system").note_found(table.concat(names, ", ")) end) end
    return table.concat(out, ". ")
end

-- A point-of-interest event: title and description only; its options are
-- read one at a time as focus moves (events.lua).
-- The resources named by the reward icons under path, in order
-- ("MI_UI_Duranium_WhiteNoBG" -> Duranium).
-- An image's brush asset name, or nil. Every step is checked: an unchecked
-- brush read is an access violation that pcall cannot catch (it crashed the
-- game on a Q Trial's Repair Station in events.lua, 2026-10-14).
local function icon_name(img)
    local name = nil
    pcall(function()
        if not (img and img:IsValid()) then return end
        local ro = img.Brush.ResourceObject
        if ro and ro:IsValid() then name = ro:GetFName():ToString() end
    end)
    return name
end

local function reward_resources(path)
    local out = {}
    for _, r in ipairs(FindAllOf("WBP_PoIMultipleChoice_Reward_C") or {}) do
        local rp = r:IsValid() and path_of(r)
        if rp and rp:sub(1, #path + 1) == path .. "." and screen.shown(r) then
            local icon = icon_name(r.Reward_Image)
            out[#out + 1] = icon and icon:match("^MI_UI_(%a+)") or "resources"
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
    -- Each reward row (WBP_PoIMultipleChoice_Reward) is read on its own:
    -- pairing amounts and lines by position read "445 Deuterium stored in
    -- total. 137 Deuterium, 65% of the maximum" for "+445, 65% reward
    -- distribution; -308 lost due full storage; +137 in total stored", and
    -- the loss (WasteAmount_Text in the first row) was never said
    -- (2026-10-14). Rows are said as the screen orders them: the reward,
    -- its loss, then what was stored.
    local rows = {}
    for _, r in ipairs(FindAllOf("WBP_PoIMultipleChoice_Reward_C") or {}) do
        local rp = r:IsValid() and path_of(r)
        if rp and rp:sub(1, #path + 1) == path .. "." and screen.shown(r) then
            local function txt(w) local ok, s = pcall(function() return w:GetText():ToString() end); return ok and s or "" end
            local amount = txt(r.RewardAmount_Text):gsub("^%+", "")
            local line = txt(r.RewardDistribution_Text)
            local waste = ""
            pcall(function() if screen.shown(r.WasteAmount_Text) then waste = txt(r.WasteAmount_Text):gsub("^%-", "") end end)
            local icon = icon_name(r.Reward_Image)
            local res = (icon and require("text").icon_name(icon)) or "resources"
            -- By shape, not English words: in German the lines are "65%
            -- Belohnungsverteilung" and "insgesamt gelagert" (VM, 2026-10-16).
            -- The rate line has a percentage; the other line is the total.
            local pct = line:match("(%d+)%%")
            local stored = not pct and (line:find("in total stored", 1, true) ~= nil or line:match("%a") ~= nil)
            local text
            -- The game's "65% reward distribution" is the outcome's rate, and
            -- "of the possible reward" contradicted the option's "Up to 447"
            -- when 447 came (demo, VM, 2026-10-15); the outcome says it.
            if pct then text = amount .. " " .. res
            elseif stored then text = amount .. " " .. res .. " stored"
            else text = amount .. " " .. res .. (line ~= "" and (", " .. line) or "") end
            if waste ~= "" and waste ~= "0" then text = text .. ". " .. waste .. " " .. res .. " lost, storage full" end
            -- Template rows left over: "#999 deuterium" and "0 duranium"
            -- after "80 duranium lost, storage full" (Asteroid Field, Q
            -- Trial, VM, 2026-10-16). Only rows with a real amount count.
            local real = amount:match("^%-?[%d,%.]+$") and (amount:match("[1-9]") or (waste ~= "" and waste ~= "0"))
            if real then rows[#rows + 1] = { text = text, last = stored } end
        end
    end
    table.sort(rows, function(a, b) return (not a.last) and b.last end)
    -- With nothing lost, the reward and what was stored are the same number:
    -- "400 food. 400 food stored." (Q Trials, Casey's machine, 2026-10-16).
    -- Only the stored line is said then.
    local stored_text = {}
    for _, r in ipairs(rows) do if r.last then stored_text[r.text] = true end end
    for _, r in ipairs(rows) do
        if r.last or not stored_text[r.text .. " stored"] then out[#out + 1] = r.text end
    end
    -- Items gained (WBP_ItemRewards_EventDetails: ItemNameTextBlock, maybe
    -- an amount); not read before, so an item reward was silent (found by
    -- the asset scan, 2026-10-16; not yet met in play).
    for _, cls in ipairs({ "WBP_ItemRewards_EventDetails_C", "WBP_ItemReward_ResourceReport_C" }) do
        for _, r in ipairs(FindAllOf(cls) or {}) do
            if r:IsValid() and screen.inside(r, path) and screen.shown(r) then
                local okn, n = pcall(function() return r.ItemNameTextBlock:GetText():ToString() end)
                local amount = ""
                pcall(function() amount = r.ItemAmountTextBlock:GetText():ToString() end)
                if okn and n and n ~= "" and n ~= "Item Name" then
                    out[#out + 1] = "Item: " .. require("text").prep(n):gsub("^%s+", "") .. (amount ~= "" and (" " .. amount) or "")
                end
            end
        end
    end
    -- Consequences in their own rich text lines ("FOOD +200", "5 CREW got
    -- Severely injured"), which were never read (Planet of Plenty, Q
    -- Trial, VM, 2026-10-14). Unfilled templates ("{TechName} unlocked")
    -- are skipped.
    local said = {}
    for _, p in ipairs(parts) do
        if p.name == "CommonRichTextBlock" and not p.text:find("{", 1, true) and not said[p.text] then
            said[p.text] = true
            -- "FOOD -150 food" once the icon became a word (text.lua):
            -- "-150 food" (Trading Station, VM, 2026-10-15).
            local name, amount, word = p.text:match("^(%u[%u%s%-]*) ([%+%-][%d,]+) (%a[%a%s%-]*)$")
            out[#out + 1] = (name and name:lower() == word:lower()) and (amount .. " " .. word) or p.text
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
            -- The DISMANTLED column's box is named Removed: a cleared ruined
            -- room was left out of the report (2026-10-14).
            if section == "Removed" then section = "Dismantled" end
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
    -- ENTER SHIP is not always there (a repair alone had only CLOSE,
    -- 2026-10-14): only mention it when another button is shown.
    local report, other = shown_widget("WBP_ConstructionInfoWidget_C"), false
    if report then
        local prefix = path_of(report) .. "."
        for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
            if b:IsValid() and path_of(b):sub(1, #prefix) == prefix and screen.shown(b)
                and b:GetFName():ToString() ~= "CloseButton" then
                other = true
            end
        end
    end
    out[#out + 1] = "Close finishes all actions, activates the rooms and collects resources"
        .. (other and "; Enter Ship lets you manage it yourself" or "")
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
    -- A range's closing bracket is its own text and dropped, which left
    -- "Low Morale (0 - 800" (VM, 2026-10-15): "Low Morale 0 to 800".
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", ""):gsub("%(([%d,]+) %- ([%d,]+)%)?", "%1 to %2") end
    return table.concat(out, ". ") .. "."
end

-- The Overview (WBP_OverviewInfoWidget, read 2026-10-11): its tab bar,
-- then the selected tab's content. Left and Right switch tabs (focus.lua).
local OVERVIEW_SKIP = { ScreenName_Text = true, CommonTextBlock_30 = true, CommonTextBlock_18 = true }
-- Numbers that have no label of their own on screen (the label is an icon
-- or a position), said with one.
local OVERVIEW_LABELS = {
    ConsumedDeuteriumText = "The warp core uses %s deuterium per cycle",
    -- Its own sentence: ". and produces" (VM, 2026-10-15).
    ProducedEnergyText = "It produces %s energy",
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
    -- The Heroes tab is walked hero by hero (view.lua); read whole, its
    -- ranks came out beside the wrong names and every selection read the
    -- whole tab again (VM, 2026-10-15).
    if tab and tab:lower():find("hero", 1, true) then
        local n = 0
        pcall(function() n = require("view").hero_count() end)
        return "Overview, " .. tab .. " tab. " .. n .. " heroes. Up and Down choose one and read its details."
    end
    -- The Combat tab is two tables (rooms, how many, their combat power)
    -- and a sum; read as a flat list it came out "combat power 0 of 12 ...
    -- Hull 0.112 of 400" (VM, 2026-10-15).
    if tab and tab:lower():find("combat", 1, true) then
        local panel = nil
        for _, x in ipairs(FindAllOf("WBP_Combat_Overview_C") or {}) do
            if x:IsValid() and path_of(x):find("^/Engine/Transient%.") and screen.shown(x) then panel = x end
        end
        if panel then
            local pairs_ = ordered_texts(panel, function(name, s) return name .. "=" .. s end)
            local seq = {}
            for _, p in ipairs(pairs_) do
                local n, v = p:match("^([%w_]+)=(.*)$")
                if n then seq[#seq + 1] = { n = n, v = v } end
            end
            local out, i = {}, 1
            local by = {}
            for _, e in ipairs(seq) do by[e.n] = by[e.n] or e.v end
            -- Each table: header, then label/count pairs, then a power column.
            local function table_at(header)
                local start = nil
                for k, e in ipairs(seq) do if e.n == header then start = k end end
                if not start then return nil end
                local labels, counts, powers, k = {}, {}, {}, start + 1
                while seq[k] and seq[k].n == "txt_Label" and seq[k + 1] and seq[k + 1].n == "txt_Count" do
                    labels[#labels + 1], counts[#counts + 1] = seq[k].v, seq[k + 1].v
                    k = k + 2
                end
                if seq[k] and seq[k].n:find("^col_CPWR") then k = k + 1 end
                while seq[k] and seq[k].n == "txt_Count" and #powers < #labels do powers[#powers + 1] = seq[k].v k = k + 1 end
                local rows = {}
                for r, l in ipairs(labels) do
                    rows[#rows + 1] = l .. ", " .. counts[r] .. " built" .. (powers[r] and (", combat power " .. powers[r]) or "")
                end
                return table.concat(rows, "; ")
            end
            local def, off = table_at("col_defense"), table_at("col_Offense")
            out[#out + 1] = "Overview, " .. tab .. " tab"
            if def then out[#out + 1] = "Defense: " .. def end
            if off then out[#out + 1] = "Offense: " .. off end
            if by.TECH_PWR then out[#out + 1] = "Tech combat power " .. by.TECH_PWR end
            if by.HULL_PWR then out[#out + 1] = "Defensive combat power " .. (by.Def_PWR or by.HULL_PWR) .. ", from hull " .. by.HULL_PWR end
            if by.OFF_PWR then out[#out + 1] = "Offensive combat power " .. by.OFF_PWR .. (by.BATT_PWR and (", base attack power " .. by.BATT_PWR) or "") end
            if by.WarpCoreTier then out[#out + 1] = "Warp core " .. by.WarpCoreTier:lower() end
            if by.ReqCE_Value then out[#out + 1] = "Required combat energy " .. by.ReqCE_Value:gsub("/", " of ") end
            if by.reduction then out[#out + 1] = "Combat power lost to missing energy " .. by.reduction end
            if by.ACP then out[#out + 1] = "Combat ally " .. by.ACP end
            if by.TCP then out[#out + 1] = "Voyager combat power " .. by.TCP .. (by.avgNmyPwr and (", against average enemy power " .. by.avgNmyPwr) or "") end
            return table.concat(out, ". ") .. "."
        end
    end
    local level = nil   -- Heroes tab: "Lv. 1" comes before the name it belongs to
    local texts = ordered_texts(w, function(name, t)
        if OVERVIEW_LABELS[name] then
            -- "uses -24 deuterium": the sign is in "uses" already.
            local v = t:gsub("^%+", ""):gsub("/$", "")
            if name == "ConsumedDeuteriumText" then v = v:gsub("^%-", "") end
            return string.format(OVERVIEW_LABELS[name], v)
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
    -- The Q Trials tab: "Q Challenges. Q Challenges. (Active 0/10)" (VM,
    -- 2026-10-15): a text the same as the one before it is dropped, and
    -- "(Active 0/10)" reads "Active 0 of 10".
    local kept = {}
    for _, t in ipairs(texts) do
        t = t:gsub("^%((Active) (%d+)/(%d+)%)$", "%1 %2 of %3")
        if t ~= kept[#kept] then kept[#kept + 1] = t end
    end
    return join_numbers(kept)
end

M.ordered_texts = ordered_texts

-- A personal log with a tab per officer (WBP_LogEventWidget_Multitab:
-- Header, TextBlock; tabs WBP_CommonButton_RoomMgmt_V2 with Previous and
-- NextTabButton). Only "Close" was read, and the open log kept Set course
-- from working (Maneuvers, VM, 2026-10-15). Left and Right switch tabs.
local function log_multitab(_, path)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return "" end
    local by = {}
    for _, t in ipairs(ordered_texts(w, function(name, s) return name .. "=" .. s end)) do
        local n, v = t:match("^([%w_]+)=(.*)$")
        if n and not by[n] then by[n] = v end
    end
    local tabs, cur = 0, nil
    for _, b in ipairs(FindAllOf("WBP_CommonButton_RoomMgmt_V2_C") or {}) do
        local bp = b:IsValid() and path_of(b)
        if bp and bp:sub(1, #path + 1) == path .. "." and screen.shown(b) then
            tabs = tabs + 1
            local ok, sel = pcall(function() return b:GetSelected() end)
            if ok and sel then pcall(function() cur = b.ButtonName:GetText():ToString() end) end
        end
    end
    local out = {}
    if by.Header then out[#out + 1] = by.Header end
    if tabs > 1 then out[#out + 1] = (cur and (cur .. " tab") or "Tab") .. ", Left and Right switch logs" end
    -- The body is not spoken: the game plays the officer reading the log
    -- (Casey, 2026-10-15, "the personal log has audio").
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- Left and Right on an open multitab log. True when handled.
function M.log_tab(dir)
    for _, w in ipairs(FindAllOf("WBP_LogEventWidget_Multitab_C") or {}) do
        local wp = w:IsValid() and path_of(w)
        if wp and wp:find("^/Engine/Transient%.") and screen.shown(w) then
            local want = dir < 0 and "PreviousTabButton" or "NextTabButton"
            for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
                local bp = b:IsValid() and path_of(b)
                if bp and bp:sub(1, #wp + 1) == wp .. "." and bp:find("%." .. want .. "$") then
                    b:HandleButtonPressed()
                    b:HandleButtonReleased()
                    b:HandleButtonClicked()
                end
            end
            ExecuteInGameThreadWithDelay(300, function()
                pcall(function()
                    local t = log_multitab(nil, wp)
                    last_text[wp] = t
                    speech.say_long(t, true)
                end)
            end)
            return true
        end
    end
    return false
end

-- Auto Resolve's window (WBP_CombatAutoResolve, Q Trials ambush, VM,
-- 2026-10-15) was silent but for "Proceed": "Combat autoresolve. Combat
-- power 95 against 73. Hull 400. Survival chance 100%. Torpedoes added 0 of
-- 7." Its buttons are the list (torpedoes, Manual Combat, Proceed).
local function auto_resolve(_, path)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return "" end
    local by = {}
    for _, t in ipairs(ordered_texts(w, function(name, s) return name .. "=" .. s end)) do
        local n, v = t:match("^([%w_]+)=(.*)$")
        if n and not by[n] then by[n] = v end
    end
    local out = { "Combat autoresolve" }
    if by.PlayerScoreText_ then out[#out + 1] = "Combat power " .. by.PlayerScoreText_ .. (by.EnemyScoreText_ and (" against " .. by.EnemyScoreText_) or "") end
    if by.Voyager_Hull then out[#out + 1] = "Hull " .. by.Voyager_Hull end
    if by.success_chance_value then out[#out + 1] = "Survival chance " .. by.success_chance_value:gsub("%%$", "") .. "%" end
    if by.TorpedoCountText then out[#out + 1] = "Torpedoes added " .. by.TorpedoCountText .. (by.TorpedoCountMax and (" of " .. by.TorpedoCountMax) or "") end
    return table.concat(out, ". ") .. "."
end
M.auto_resolve_text = function(path) return auto_resolve(nil, path) end

-- A Q Trial's sector reward cards (WBP_MetaProgressionReward: technology,
-- hero or resources). Their buttons have no text, so the results screen
-- had nothing to choose and Confirm stayed disabled (VM, 2026-10-15).
function M.meta_reward_label(b, path)
    local cp = path:match("^(.-WBP_MetaProgressionReward_C_%d+)%.")
    local card = cp and StaticFindObject(cp)
    if not (card and card:IsValid()) then return nil end
    local by, res = {}, {}
    local pending = nil
    for _, t in ipairs(ordered_texts(card, function(name, s) return name .. "=" .. s end)) do
        local n, v = t:match("^([%w_]+)=(.*)$")
        if n then
            if n == "ResourceNameTextBlock" then pending = v
            elseif n == "ResourceAmountTextBlock" and pending then res[#res + 1] = pending .. " +" .. v:gsub("^%+", "") pending = nil
            elseif not by[n] then by[n] = v end
        end
    end
    local out = {}
    local kind = by.TypeText or "Reward"
    if by.TechName then
        out[#out + 1] = kind .. ": " .. by.TechName .. (by.NewText and ", new" or "")
        local where = {}
        if by.TechTreeName then where[#where + 1] = by.TechTreeName end
        if by.TierNr_TXT then where[#where + 1] = (by.TierNr_TXT:gsub("0(%d)", "%1")) end
        if #where > 0 then out[#out + 1] = table.concat(where, ", ") end
        if by.TechDesc then out[#out + 1] = by.TechDesc end
    elseif by.HeroName_TXT then
        local head = kind .. ": " .. by.HeroName_TXT
        if by.HeroLevel_TXT then head = head .. ", " .. by.HeroLevel_TXT:gsub("0(%d)", "%1"):lower() end
        if by.TraitText then head = head .. ", " .. by.TraitText end
        out[#out + 1] = head
        local skills = ""
        pcall(function() skills = require("rooms").skills_of(card.HeroStatSheet) end)
        if skills ~= "" then out[#out + 1] = skills end
        if by.HeroCombatAbility_TXT then out[#out + 1] = "Combat ability: " .. by.HeroCombatAbility_TXT end
    elseif by.AmusementName then
        -- A Q Modifier card: its name and what it does ("Party Ship" was
        -- read only as "Q Modifier", VM, 2026-10-16).
        out[#out + 1] = kind .. ": " .. by.AmusementName
        if by.AmusementDesc then out[#out + 1] = by.AmusementDesc end
    elseif #res > 0 then
        out[#out + 1] = kind .. ": " .. table.concat(res, ", ")
    else
        out[#out + 1] = kind
    end
    -- The game shows the choice only by a highlight and the "(01/01)"
    -- count, so the mod remembers the card Enter was pressed on.
    if M.meta_chosen == path and M.meta_reward_count():match("^[1-9]") then out[1] = out[1] .. ", chosen" end
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- "1 of 1" from the results screen's "(01/01)", or "".
function M.meta_reward_count()
    for _, w in ipairs(FindAllOf("WBP_SandboxSectorResult_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
            local s = text_of_widget(w.RewardAmount_TXT)
            local a, b = s:match("(%d+)%s*/%s*(%d+)")
            if a then return tonumber(a) .. " of " .. tonumber(b) end
        end
    end
    return ""
end

-- Tutorials describe the mouse and what is seen ("Open the OVERVIEW
-- screen"). After a tutorial's page the mod says its own keys for the same
-- thing (Casey, 2026-10-11). Keyed by the tutorial's title.
local TUTORIAL_KEYS = {
    -- Every tutorial in the game's DT_TutorialLibraryData (51, dumped
    -- 2026-10-15); Combat Camera and Replacement Characters have nothing to
    -- press. The full game opens Main Engineering on its Warp Core tab and
    -- the demo on the first tab, so the tab is named, not counted.
    ["Activate Room"] = "in the ship view, choose the room with the arrows or from the J room list, press Enter, then Enter on its power button",
    ["Help"] = "F1 lists the keys for the screen you are on, Control plus F1 lists every key, I says where you are, and R repeats what was last read",
    ["System Map Navigation"] = "V switches between the ship and the System Map; on the map, Up and Down move through the points and Enter opens Scan and Set course",
    ["Sector Map"] = "press N and choose Sector map; Up and Down move through the star systems, the one with the main mission says so, and Enter opens Scan and Set course",
    ["Scan"] = "on the System Map, choose a point with Up and Down, press Enter, then Enter on Scan",
    ["Points of Interest"] = "Up and Down move between the options, and each says its rewards and its chances of a good or bad outcome; Enter picks one",
    ["Basic Resources"] = "C reads your resources",
    ["Warp Core"] = "open Main Engineering with Enter; on its Warp Core tab (Left and Right switch tabs), Up and Down choose the tier and Enter sets it",
    ["Gray Mode"] = "C reads your Deuterium and energy",
    ["Repairing Rooms"] = "choose the damaged room in the ship view or from the J room list, press Enter, then Enter on Repair",
    ["Transporter Room"] = "on the away team screen, Up and Down move between the slots and Enter chooses a hero; once every slot is filled, Enter starts the mission",
    ["Away Mission"] = "Up and Down walk the choices, their heroes and Confirm. Enter on a hero selects them; Enter on Confirm confirms",
    ["Fatigue"] = "a hero's fatigue is said in away mission results; N, Overview, then the Heroes tab lists your heroes",
    ["Away Mission Risks"] = "a dangerous choice says its danger level, out of 3; Up and Down walk the choices and Enter on Confirm confirms",
    ["Away Mission - Advanced"] = "Up and Down walk the choices, their heroes and Confirm. Enter on a hero selects them; Enter on Confirm confirms",
    ["Consequences"] = "Up and Down move between the options, and each says its outcome odds; a major decision says so, and Enter holds it for you",
    ["Morale"] = "press N, choose Overview, then press Right to reach the Morale tab",
    ["Life Support"] = "rooms say on or off as you move through the decks; open Life support with Enter and press Enter on its power button",
    ["Engineering Office"] = "choose the Engineering Office in the ship view and press Enter to open it",
    ["Clear Debris"] = "ruined rooms are not in the J room list; in the ship view, move to one with the arrows, press Enter, then Enter on Clear debris",
    ["Build Rooms"] = "in the ship view, move to an empty building space with the arrows and press Enter; Up and Down choose a category, Enter opens it, Up and Down choose a room and Enter builds it",
    ["Crew"] = "C reads your crew along with your resources",
    ["Science Lab"] = "open the Science Lab with Enter and press Enter on Research, or press N and choose Research; Up and Down choose a technology, Enter opens it and Enter again begins the research",
    ["Sickbay"] = "open Sickbay with Enter; its Manage Patients tab (Left and Right switch tabs) reads each patient with their condition and the cycles to recover",
    ["Batteries"] = "C reads your energy and battery; to build a Battery Compartment, move to an empty building space in the ship view and press Enter",
    ["Workshop"] = "open the Workshop with Enter; on its Crafting tab (Left and Right switch tabs), Up and Down move through the items and buttons and Enter uses one",
    ["Tech Tree"] = "press N and choose Research; Up and Down move through the tiers, then the technologies; Left and Right switch category; Enter opens an item and Enter again begins the research",
    ["Hull"] = "C reads your hull; to repair it, open the Engineering Office in the ship view with Enter",
    ["Upgrade Room"] = "choose the Mess Hall in the ship view or from the J room list, press Enter, then Enter on Upgrade",
    ["Replicator Food"] = "open the Mess Hall with Enter; on its Food Serving tab (Left and Right switch tabs), Up and Down choose the rations and Enter selects them",
    ["Normal Food rations"] = "open the Mess Hall with Enter; on its Food Serving tab (Left and Right switch tabs), Up and Down choose normal rations and Enter selects them",
    ["Assign Hero"] = "open the room with Enter and press Enter on its hero slot; Up and Down choose a hero and Enter assigns them; Backspace closes the hero list",
    ["Combat Hero Selection"] = "Up and Down move between the hero slots; Enter on a slot opens the hero list, and Enter chooses a hero",
    ["Start of Combat"] = "Enter opens Orders, where Up and Down move and Enter picks; Shift fires a torpedo; I reads both ships",
    ["Open Command Menu"] = "Enter opens Orders; in the order wheel, Up and Down move, Enter picks, and Back is last",
    ["Command Menu"] = "in the Orders wheel, Up and Down move between the orders and Enter picks one; Back is last",
    ["Attack Movement"] = "I reads both ships; in the Orders wheel, Up and Down move through the offensive actions and Enter picks one",
    ["Hero Abilities"] = "the number keys use the heroes' abilities; abilities turning active or ready are said as they happen, and I reads them",
    ["Torpedoes"] = "Shift fires a torpedo; I reads the torpedoes left",
    ["Defensive Movement"] = "Enter opens Orders; choose the defensive actions with Up and Down and Enter; I reads both ships",
    ["Combat Repairs"] = "Enter opens Orders; choose the repair action with Up and Down and Enter, then choose the system the same way",
    ["Energy Management"] = "Left and Right pick a system, and Up and Down move energy to it",
    ["Cargo Bay"] = "C reads each resource with its storage limit",
    ["Trading"] = "open the Aeroshuttle Bay with Enter; Up and Down move through its buttons and Enter uses one",
    ["Combat Allies"] = "open the Bridge with Enter; on its Combat Allies tab (Left and Right switch tabs), Up and Down move through the allies, each read with its combat power, recruitment cost and upkeep, and Enter chooses one",
    ["Ex-Borg"] = "C reads your crew; to build alcoves, move to an empty building space in the ship view and press Enter",
    ["Heroes"] = "Up and Down move between the options; Left and Right choose a hero, No hero first, and Enter picks the option with that hero",
    ["Sector Goals and Exits"] = "O reads the sector goal; in Q Trials, press N and choose Leave sector to pick an exit",
    ["Q-Modifiers"] = "on the Q Trials setup, Up and Down move to Q Modifier and Enter opens its choices; Up and Down choose one and Enter picks it",
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

-- The game's mouse, controller and screen-position wording is left out of
-- tutorials, and the keys follow instead (Casey, 2026-10-15: keyboard
-- commands rather than the visual icon descriptions). "Click on the
-- question mark icon on the left of the screen to revisit any tutorial
-- screen (on controller press d-pad left two times)" and "in the lower
-- left part of the ship" told a keyboard player nothing.
function M.clean_tutorial(text)
    -- Colours used as labels: "Yellow: Average outcomes ... Orange & Red:
    -- Bad and terrible outcomes" (Points of Interest, Q Trials, VM,
    -- 2026-10-15). The words after the colour say it all.
    local COLOURS = { green = true, yellow = true, orange = true, red = true, blue = true, purple = true, white = true, gold = true }
    text = text:gsub("(%a+)%s*&%s*(%a+):%s*", function(a, b)
        if COLOURS[a:lower()] and COLOURS[b:lower()] then return "" end
    end)
    text = text:gsub("(%a+):%s+", function(a)
        if COLOURS[a:lower()] then return "" end
    end)
    -- Controller hints in brackets.
    text = text:gsub("%s*%([^%)]*[Cc]ontroller[^%)]*%)", ""):gsub("%s*%([^%)]*[Gg]amepad[^%)]*%)", "")
    -- Where something sits on the screen.
    -- Only exact position phrases: a loose pattern from the first "in the"
    -- to "of the screen" would have taken real words with it (review,
    -- 2026-10-15).
    for _, prep in ipairs({ "in the", "on the", "at the" }) do
        for _, pos in ipairs({ "left", "right", "top", "bottom", "middle", "center", "upper left", "upper right",
                               "lower left", "lower right", "top left", "top right", "bottom left", "bottom right" }) do
            for _, tail in ipairs({ "of the screen", "part of the screen", "side of the screen", "corner of the screen",
                                    "part of the ship", "side of the ship" }) do
                local phrase = " " .. prep .. " " .. pos .. " " .. tail
                local at = text:find(phrase, 1, true)
                while at do
                    text = text:sub(1, at - 1) .. text:sub(at + #phrase)
                    at = text:find(phrase, 1, true)
                end
            end
        end
    end
    -- Sentences that are only about the mouse or an icon.
    local kept = {}
    for s in (text .. " "):gmatch("(.-[%.!%?])%s+") do
        local l = s:lower()
        -- Also controller and colour wording the scan of every tutorial
        -- found ("On controller use RB/LB", "a blue countdown", "marked with
        -- a golden outline", "white question marks", 2026-10-15).
        local mouse = l:find("%f[%a]click") or l:find("%f[%a]hover") or l:find("%f[%a]drag")
            or l:find("%f[%a]mouse") or l:find("%f[%a]icon") or l:find("%f[%a]controller")
            or l:find("%f[%a]gamepad") or l:find("golden outline", 1, true) or l:find("question mark", 1, true)
            or l:find("%f[%a]colou?rs?%f[%A]") or l:find("%f[%a]blue%f[%A]") or l:find("%f[%a]green%f[%A]")
        if not mouse then kept[#kept + 1] = s end
    end
    local tail = (text .. " "):gsub("^.*[%.!%?]%s+", "")
    if tail:find("%S") then kept[#kept + 1] = tail end
    return (table.concat(kept, " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function tutorial_page(parts)
    local out = {}
    for _, p in ipairs(parts) do out[#out + 1] = p.text end
    local text = M.clean_tutorial(table.concat(out, ". "))
    local title = tutorial_title()
    local keys = title and TUTORIAL_KEYS[title]
    if keys then
        text = (text ~= "" and (text:gsub("[%.%s]+$", "") .. ". ") or "") .. "With Voyager Access: " .. keys .. "."
    end
    return text
end

-- The Energy Loss Report (Gray Mode, 2026-10-14) was read as a soup of
-- labels and numbers. In visual order it is a title, the reason, the two
-- column heads, then rows of prior value, label, current value.
local function energy_loss(_, path)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return "" end
    -- "Deuterium depleted\nEntering gray mode" is one block, its line break
    -- gone by now: a capital after a lowercase word starts the next
    -- sentence. Only in that block: applied to every text it read "Phaser.
    -- Control. Room" (full game, VM, 2026-10-14). The deactivated rooms
    -- ("Phaser Control Room -9, Sickbay -7") say what energy each used.
    local t = ordered_texts(w, function(name, s)
        if name == "EnergyLossReason" then return (s:gsub("(%l) (%u)", "%1. %2")) end
        -- The shared clean-up (text.lua) may already have named the icon:
        -- "9 energy energy" (VM, 2026-10-15).
        if name == "RoomsLost" then return (s:gsub(" %-%s*(%d+)", " %1 energy"):gsub("energy energy", "energy")) end
        return false
    end)
    local out, rows = {}, {}
    local reason_at = nil
    local i = 1
    while i <= #t do
        local a, label, b = t[i], t[i + 1], t[i + 2]
        if a and label and b and a:match("^%-?%d+$") and b:match("^%-?%d+$") and not label:match("^%-?%d+$") then
            local l = label:sub(1, 1):upper() .. label:sub(2)
            -- "max. activatable " is the first line of "Max. activatable
            -- warp core tier"; the rest is drawn, not text.
            l = l:gsub("activatable%s*$", "activatable warp core tier")
            rows[#rows + 1] = string.format("%s %s, was %s", l, b, a)
            i = i + 3
        elseif t[i] == "Deck" then
            -- The deck number is a digit per box: "Deck. 0. 5".
            local digits = ""
            i = i + 1
            while t[i] and t[i]:match("^%d$") do digits, i = digits .. t[i], i + 1 end
            out[#out + 1] = "Deck " .. (tonumber(digits) or digits)
            if t[i] and not t[i]:match("^%-?%d+$") then
                out[#out] = out[#out] .. ": " .. t[i]
                i = i + 1
            end
        else
            if not t[i]:find("State$") then
                out[#out + 1] = t[i]
                if not reason_at and t[i]:find("%. %u") then reason_at = #out end
            end
            i = i + 1
        end
    end
    -- The before and after numbers belong with the reason, before the
    -- list of rooms switched off.
    local at = (reason_at or #out) + 1
    for k, r in ipairs(rows) do table.insert(out, at + k - 1, r) end
    for k, s in ipairs(out) do out[k] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- The Research Report came out in storage order with its buttons
-- ("Items researched. rewards. Research Report. CLOSE REPORT. ENTER SHIP.
-- Transporter signal amplifier", 2026-10-14). Visual order instead; the
-- rewards themselves are a second window (WBP_ResearchReport) read next.
-- The rewards (WBP_ResearchReport): "Rewards: 100 Food. New craftable item:
-- Apples & Roots". A resource is an icon and a number; it was read as
-- "Resources. +100" with no name, twice over (full game, VM, 2026-10-14).
local function research_rewards()
    local report = shown_widget("WBP_ResearchReport_C")
    if not report then return "" end
    local prefix = path_of(report) .. "."
    local res, items = {}, {}
    for _, r in ipairs(FindAllOf("WBP_ResourceReward_ResearchReport_C") or {}) do
        local rp = r:IsValid() and path_of(r)
        if rp and screen.inside(r, prefix:sub(1, -2)) and screen.shown(r) then
            local icon = icon_name(r.ResourceImage)
            local name = (icon and require("text").icon_name(icon)) or "resources"
            local amount = text_of_widget(r.ResourceAmountTextBlock):gsub("^%+", "")
            if amount ~= "" then res[#res + 1] = amount .. " " .. name end
        end
    end
    for _, r in ipairs(FindAllOf("WBP_ItemReward_ResourceReport_C") or {}) do
        local rp = r:IsValid() and path_of(r)
        if rp and screen.inside(r, prefix:sub(1, -2)) and screen.shown(r) then
            local item = text_of_widget(r.ItemNameTextBlock)
            if item ~= "" then items[#items + 1] = item end
        end
    end
    local out = {}
    if #res > 0 then out[#out + 1] = "Rewards: " .. table.concat(res, ", ") end
    if #items > 0 then
        out[#out + 1] = (#items == 1 and "New craftable item: " or "New craftable items: ") .. table.concat(items, ", ")
    end
    return table.concat(out, ". ")
end

local function research_info(_, path)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return "" end
    local head = text_of_widget(w.HeaderTextBlock)
    local title = ""
    pcall(function() title = text_of_widget(w.ContentWidget.Title) end)
    local out = { head ~= "" and head or "Research Report" }
    if title ~= "" then out[#out + 1] = "Items researched: " .. title end
    local rewards = research_rewards()
    if rewards ~= "" then out[#out + 1] = rewards end
    -- The demo's report: what it has beyond the above, in layout order.
    if title == "" then
        local t = ordered_texts(w)
        if t[#t] and t[#t]:lower() == "rewards" then t[#t] = nil end
        return (table.concat(t, ". "):gsub("Items researched%. ", "Items researched: ")) .. "."
    end
    return table.concat(out, ". ") .. "."
end

-- The battle result (WBP_BattleResultLCARS) read in layout order: "Injuries.
-- Fled. Hull Status. 59. Damaged Rooms. None. Combat Result:. Proceed"
-- (2026-10-14). The lists are BattleResultListViewItem widgets placed after
-- their headings (injured_headline is Injuries, injured_headline_1 Damaged
-- Rooms); Win_Text or Lose_Text is the outcome.
local function battle_result(_, path)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return "" end
    local W = StaticFindObject("/Script/UMG.UserWidget")
    local PANEL = StaticFindObject("/Script/UMG.PanelWidget")
    local BTN = StaticFindObject("/Script/CommonUI.CommonButtonBase")
    local outcome, hull, section, pending_amount, pending_name = nil, nil, nil, nil, nil
    local lists, order = {}, {}
    local HEAD = { injured_headline = "Injuries", injured_headline_1 = "Damaged rooms" }
    local function walk(x, depth)
        if depth > 30 or not (x and x:IsValid()) or not screen.shown(x) or x:IsA(BTN) then return end
        local ok, txt = pcall(function() return x:GetText():ToString() end)
        if ok and type(txt) == "string" then
            local name, t = x:GetFName():ToString(), plain(txt)
            if t == "" or t == "+" then return end
            -- A reward's amount and its name are two texts: "50 Morale".
            -- Either can come first in the layout.
            if name == "ResourceAmountTextBlock" then
                if not pending_name then pending_amount = t return end
                t = t .. " " .. pending_name
                pending_name = nil
            elseif name == "ResourceNameTextBlock" then
                if not pending_amount then pending_name = t return end
                t = pending_amount .. " " .. t
                pending_amount = nil
            end
            -- "Gained" is ResourcesGained.Headline_Text; "headline_text" never
            -- matched, so the rewards ran into the injuries ("Injuries, 4:
            -- None, Gained, Morale, 50", VM, 2026-10-14).
            if HEAD[name] or name:lower() == "headline_text" then
                section = HEAD[name] or t
                if not lists[section] then lists[section] = {} order[#order + 1] = section end
            -- "Destroyed" or "Fled" alone did not say who won (2026-10-14).
            elseif name == "Win_Text" then outcome = "victory, " .. t:lower()
            elseif name == "Lose_Text" then outcome = "defeat, " .. t:lower()
            elseif name == "HullStatus_Percent" then hull = t
            elseif section and name ~= "CombatHeroSelectionHeader" and name ~= "TextBlock_103"
                and name ~= "TextBlock_1" and name ~= "SplitRewards" then
                table.insert(lists[section], t)
            end
            return
        end
        if x:IsA(W) then
            local tree = x.WidgetTree
            if tree and tree:IsValid() and tree.RootWidget then walk(tree.RootWidget, depth + 1) end
        elseif x:IsA(PANEL) then
            for i = 0, x:GetChildrenCount() - 1 do walk(x:GetChildAt(i), depth + 1) end
        end
    end
    walk(w, 0)
    local out = { "Combat result: " .. (outcome or "over") }
    if hull then out[#out + 1] = "Hull status " .. hull .. "%" end
    for _, s in ipairs(order) do
        -- With a count first: 22 injured names came with no hint of how many
        -- (Q Trial defeat, VM, 2026-10-14). "None" stays as it is.
        local n = #lists[s]
        local counted = s == "Injuries" or s == "Damaged rooms"
        if n == 1 and lists[s][1]:lower() == "none" then out[#out + 1] = s .. ": none"
        elseif n > 0 and counted then out[#out + 1] = s .. ", " .. n .. ": " .. table.concat(lists[s], ", ")
        elseif n > 0 then out[#out + 1] = s .. ": " .. table.concat(lists[s], ", ") end
    end
    for k, s in ipairs(out) do out[k] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- An away mission's header read "9,680.1. System. Ocampa" (2026-10-14): the
-- label "System" (Population_1) goes with the system's name before it.
local function away_detail(parts)
    local by = {}
    for _, p in ipairs(parts) do if not by[p.name] then by[p.name] = p.text end end
    local place = by.T_POI_Name or by.LocationNameTextBlock or ""
    local system = by.SystemNameTextBlock
    local out = {}
    if place ~= "" then out[#out + 1] = place end
    if system and system ~= "" then out[#out + 1] = "system " .. system end
    if #out == 0 then return "" end
    return table.concat(out, ", ") .. "."
end

-- The side mission offer: its title (HeaderTextBlock) first; the speaker's
-- name came before it ("Neelix. Pursuit of Happiness", 2026-10-14).
local function multiple_choice(parts, path)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return "" end
    local header = nil
    for _, p in ipairs(parts) do if p.name == "HeaderTextBlock" then header = p.text end end
    local out = { header }
    for _, t in ipairs(ordered_texts(w)) do
        if t ~= header then out[#out + 1] = t end
    end
    -- Options it cannot take are skipped by Up and Down, so they are named
    -- here ("Build or upgrade an Observation Lounge", greyed out).
    for _, b in ipairs(FindAllOf("WBP_MultipleChoice_Button_C") or {}) do
        if b:IsValid() and path_of(b):find("^/Engine/Transient%.") and screen.shown(b) and not b:GetIsEnabled() then
            local bp = path_of(b) .. "."
            for _, t in ipairs(FindAllOf("RichTextBlock") or {}) do
                local tp = t:IsValid() and path_of(t)
                if tp and tp:sub(1, #bp) == bp and screen.shown(t) then
                    -- text_of does not exist here; this failed every poll and
                    -- the offer's message was never read (Q Trial, VM, 2026-10-14).
                    local s = text_of_widget(t):gsub("%s+([%.,])", "%1")
                    if s ~= "" then out[#out + 1] = "Not available: " .. s end
                end
            end
        end
    end
    for k, s in ipairs(out) do out[k] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- The end of the demo (WBP_EndOfGameMissionInfo_01): its three buttons
-- were read before its message ("KEEP EXPLORING. MAIN MENU. WISHLIST NOW!
-- Caretaker. Captain, you've reached the end of the demo!", 2026-10-14).
-- Title and message only; the buttons are the button list.
local function end_of_game(_, path)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return "" end
    local out = {}
    for _, t in ipairs(ordered_texts(w, function(name) return name == "CommonTextBlock_30" end)) do
        out[#out + 1] = t:gsub("%.%s*$", "")
    end
    return #out > 0 and (table.concat(out, ". ") .. ".") or ""
end

-- The first-launch screens read their buttons before their message
-- ("Performance Selection. LOW. MEDIUM. HIGH. EPIC. CONFIRM. Choose a
-- graphics quality...", full game, 2026-10-14). The buttons are spoken as
-- focus reaches them, so only the texts outside buttons are read here.
local function without_buttons(parts, path)
    local inside = {}
    for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
        local bp = b:IsValid() and path_of(b)
        if bp and bp:sub(1, #path + 1) == path .. "." then inside[#inside + 1] = bp .. "." end
    end
    local out, seen = {}, {}
    for _, p in ipairs(parts) do
        local in_button = false
        for _, bp in ipairs(inside) do
            if p.path:sub(1, #bp) == bp then in_button = true break end
        end
        if not in_button and not seen[p.text] then
            seen[p.text] = true
            out[#out + 1] = p.text:gsub("%.%s*$", "")
        end
    end
    return #out > 0 and (table.concat(out, ". ") .. ".") or ""
end

-- Cargo Bay swap warning: the lost stock came before the sentence that
-- introduces it ("Warning. 500 Deuterium. Due to the capacity change, you
-- would lose the following resources:", VM, 2026-10-16).
local function cargo_swap(parts, path)
    local head, info, lose = nil, nil, {}
    for _, p in ipairs(parts) do
        local name = p.path:match("([^%.]+)$") or ""
        if name:find("^HeaderTextBlock") then head = head or p.text
        elseif name == "InfoTextBlock" then info = p.text
        elseif name:find("^ResourceChange") then lose[#lose + 1] = p.text end
    end
    if not info then return without_buttons(parts, path) end
    info = info:gsub("[%s:]+$", "")
    return (head and (head .. ". ") or "") .. info .. (#lose > 0 and (": " .. table.concat(lose, ", ")) or "") .. "."
end

-- Leave Sector: "Leave Sector: Vidiian Sector. Choose next sector. 70,000
-- light years to home. Earth distance remaining 64,000 of 70,000 light
-- years." The entries are the focusable list (M.leave_sector_entry).
local function leave_sector(parts)
    local by = {}
    for _, p in ipairs(parts) do
        if not p.path:find("WBP_LeaveSectorEntry_C", 1, true) and not by[p.name] then by[p.name] = p.text end
    end
    local out = {}
    out[#out + 1] = (by.HeaderTextBlock or "Leave Sector") .. (by.SectorName and (": " .. by.SectorName) or "")
    if by.TextBlock then out[#out + 1] = by.TextBlock end
    if by.RemainingDistance_TXT_1 then out[#out + 1] = by.RemainingDistance_TXT_1 end
    if by.RemainingDistance_TXT then
        local total = (by.InitialDistance_TXT or ""):gsub("^%s*/%s*", "")
        out[#out + 1] = "Earth distance remaining " .. by.RemainingDistance_TXT .. (total ~= "" and (" of " .. total) or "")
    end
    for i, s in ipairs(out) do out[i] = s:gsub("%.$", ""):gsub("(%d) ly", "%1 light years"):gsub("(%d) LY", "%1 light years") end
    return table.concat(out, ". ") .. "."
end

-- The resource costs shown under the widget at path ("72 Tritanium"), each
-- named by its icon.
local function costs_under(path)
    local costs = {}
    local prefix = path .. "."
    for _, c in ipairs(FindAllOf("WBP_CombatAllyCost_SingleResource_C") or {}) do
        local cp = c:IsValid() and path_of(c)
        if cp and cp:sub(1, #prefix) == prefix and screen.shown(c) then
            local icon = icon_name(c.ResourceImage)
            -- Shared names: "289 science points", not "SciencePoints"
            -- (Leave Sector, Q Trial, VM, 2026-10-16).
            local res = (icon and require("text").icon_name(icon)) or "resources"
            costs[#costs + 1] = text_of_widget(c.ResourceAmount) .. " " .. res
        end
    end
    return costs
end

local function light_years(s)
    return (s:gsub("^#", ""):gsub("(%d)%s*[lL][yY]%.?$", "%1 light years"))
end

-- Leaving a campaign sector (WBP_SectorExitEventWidget, created in the VM
-- from the coverage list, 2026-10-15): "Next Sector: Hirogen-Controlled
-- Sector. Travel distance 9,999 light years. Travel cost 99 Deuterium.
-- Earth distance remaining ... Leaving the sector will cause all active
-- missions to be canceled...". SET COURSE HOME, STAY FOR NOW and the bonus
-- fuel offer are the button list (M.bonus_fuel_label).
local function sector_exit_event(parts, path)
    local by = {}
    for _, p in ipairs(parts) do
        if not p.path:find("_BTN.", 1, true) and not p.path:find("Button.", 1, true) and not by[p.name] then by[p.name] = p.text end
    end
    local out = {}
    out[#out + 1] = (by.HeaderTextBlock or "Next Sector") .. (by.HeaderTextBlock_1 and (": " .. by.HeaderTextBlock_1) or "")
    if by.Distance_TXT then out[#out + 1] = "Travel distance " .. light_years(by.Distance_TXT) end
    local costs = costs_under(path)
    if #costs > 0 then out[#out + 1] = "Travel cost " .. table.concat(costs, ", ") end
    if by.RemainingDistance_TXT then
        local total = light_years((by.InitialDistance_TXT or ""):gsub("^%s*#?%s*/%s*", ""))
        out[#out + 1] = "Earth distance remaining " .. light_years(by.RemainingDistance_TXT) .. (total ~= "" and (" of " .. total) or "")
    end
    if by.WarningText then out[#out + 1] = by.WarningText end
    for i, s in ipairs(out) do out[i] = s:gsub("%s+$", ""):gsub("%.$", "") end
    return table.concat(out, ". ") .. "."
end

-- The bonus fuel offer on the sector exit: "Use Crystalline Nucleogenic
-- Compound: costs 99, 9,999 light years bonus distance."
function M.bonus_fuel_label(b)
    local function t(w) return text_of_widget(w) end
    local out = { "Use " .. (t(b.ItemName_TXT) ~= "" and t(b.ItemName_TXT) or "bonus fuel") }
    local cost = t(b.BonusFuelCost_TXT):gsub("^#", "")
    if cost ~= "" then out[#out + 1] = "costs " .. cost end
    local dist = t(b.BonusDistance_TXT)
    dist = light_years(dist)
    if dist:match("^[%d,%.]+$") then dist = dist .. " light years" end
    if dist ~= "" then out[#out + 1] = dist .. " bonus distance" end
    return table.concat(out, ", ")
end

-- The sector exit on the map, a page of the point detail window: "Sector
-- Exit. Next Sector: ... Travel distance ... Travel cost ...".
function M.sector_exit_detail(parts)
    local by, page = {}, nil
    for _, p in ipairs(parts) do
        local pp = p.path:match("^(.-WBP_SectorExitDetailView[%w_]*)%.")
        if pp then
            page = pp
            if not by[p.name] then by[p.name] = p.text end
        end
    end
    if not page then return nil end
    local out = { by.SectorExit_TXT or "Sector Exit" }
    local name = by.SectorName_TextBlock or by.SectorName_TextBlock_1
    out[#out + 1] = (by.TextBlock_85 or "Next Sector") .. (name and (": " .. name) or "")
    if by.DistanceTravelled_TextBlock then out[#out + 1] = "Travel distance " .. light_years(by.DistanceTravelled_TextBlock) end
    local costs = costs_under(page)
    if #costs > 0 then out[#out + 1] = "Travel cost " .. table.concat(costs, ", ") end
    for i, s in ipairs(out) do out[i] = s:gsub("%s+$", ""):gsub("%.$", "") end
    return table.concat(out, ". ") .. "."
end

-- One sector to go to: "Sector 01: Trading Sector. 6,000 light years.
-- Costs 72 Tritanium, not enough." Its entry read "72, Select, Travel
-- cost, Travel Distance, Sector 01" (VM, 2026-10-14).
function M.leave_sector_entry(e)
    local function t(w) return text_of_widget(w) end
    local out = {}
    local num, name = t(e.SectorNumber_TXT), t(e.SectorName_TextBlock)
    if name == "" then name = t(e.SectorName_TextBlock_1) end
    out[#out + 1] = (num ~= "" and num or "Sector") .. (name ~= "" and (": " .. name) or "")
    local dist = t(e.DistanceTravelled_TextBlock):gsub("%s*[lL][yY]$", " light years")
    if dist ~= "" then out[#out + 1] = dist end
    local costs = costs_under(path_of(e))
    local none = t(e.NoCosts_TXT)
    if #costs > 0 then
        local affordable = true
        pcall(function() affordable = e.Affordable ~= false end)
        out[#out + 1] = "Costs " .. table.concat(costs, ", ") .. (affordable and "" or ", not enough")
    elseif none ~= "" then
        out[#out + 1] = none
    end
    if screen.shown(e.Locked_IMG) then out[#out + 1] = "Locked" end
    for i, s in ipairs(out) do out[i] = s:gsub("%.$", "") end
    return table.concat(out, ". ") .. "."
end

-- Q Trials results at the end of a sector or a trial (WBP_SandboxSectorResult,
-- first met after a defeat in the VM, 2026-10-14; only "Return to Main
-- Menu" was read). Q's remark (QuipText) is voiced and left out.
local function sandbox_result(parts)
    local by = {}
    for _, p in ipairs(parts) do if not by[p.name] then by[p.name] = p.text end end
    local out = {}
    if by.CommonTextBlock_59 then out[#out + 1] = by.CommonTextBlock_59 end
    out[#out + 1] = (by.CommonTextBlock_51 or "Trial Results") .. (by.SectorNr_TXT and (", " .. by.SectorNr_TXT) or "")
    local stats = {}
    for _, pair in ipairs({ { "Passed cycles", "passedCycles_TXT" }, { "Points of interest explored", "POIsExplored_TXT" },
        { "Technologies researched", "TechResearched_TXT" }, { "Rooms built or upgraded", "RoomsBuilt_TXT" },
        { "Time", "PlayTime_TXT" } }) do
        if by[pair[2]] then stats[#stats + 1] = pair[1] .. " " .. by[pair[2]] end
    end
    if #stats > 0 then out[#out + 1] = "Sector performance: " .. table.concat(stats, ", ") end
    if by.RemainingDistance_TXT then
        local total = (by.InitialDistance_TXT or ""):gsub("^%s*/%s*", "")
        out[#out + 1] = "Earth distance remaining " .. by.RemainingDistance_TXT .. (total ~= "" and (" of " .. total) or "")
    end
    local function nums(s) return (s:gsub("[()]", ""):gsub("%d+", function(d) return tostring(tonumber(d)) end)) end
    if by.RewardHeadText then out[#out + 1] = by.RewardHeadText .. ", " .. nums((by.RewardAmount_TXT or ""):gsub("/", " of ")) end
    if by.UnlockedRewards_TXT then out[#out + 1] = by.UnlockedRewards_TXT .. ", " .. nums(by.UnlockedRewardsAmount_TXT or "") end
    for i, s in ipairs(out) do out[i] = s:gsub("%s+$", ""):gsub("%.$", ""):gsub("(%d) LY", "%1 light years"):gsub("(%d) ly", "%1 light years") end
    return table.concat(out, ". ") .. "."
end

local LAYOUTS = { WBP_SandboxSectorResult_C = sandbox_result, WBP_LeaveSector_C = leave_sector, WBP_POIDetailView_C = poi_detail, WBP_POIMultipleChoice_C = poi_event,
    WBP_FirstPerformanceSelection_C = without_buttons, WBP_GammaCorrection_C = without_buttons,
    WBP_GameOver_C = without_buttons, WBP_NoWayBackWidget_C = without_buttons, WBP_CraftingResult_C = without_buttons,
    WBP_ConfirmationWidget_C = without_buttons, WBP_HeroUnavailableWidget_C = without_buttons,
    WBP_EngineeringOffice_Confirmation_C = without_buttons, WBP_CargoSwap_Confirmation_C = cargo_swap,
    WBP_SectorExitEventWidget_C = sector_exit_event, WBP_CombatAutoResolve_C = auto_resolve,
    WBP_LogEventWidget_Multitab_C = log_multitab,
    WBP_SectorExitDetailView_C = function(parts) return M.sector_exit_detail(parts) or "" end,
    -- Heading, then the question, then the rest: creation order put "Are
    -- you sure?" last on the second opening (2026-10-14).
    -- The warning page: its heading and message.
    WBP_Sandbox_Setup_C = function(parts)
        local head, body = nil, nil
        for _, p in ipairs(parts) do
            if p.name == "HeaderTextBlock_1" then head = p.text end
            if p.name == "Mainline" then body = p.text end
        end
        -- The setup page is read item by item (qtrials.lua).
        if not body then return "" end
        return (head and (head .. ". ") or "") .. body
    end,
    WBP_PauseMenu_Confirms_C = function(parts, path)
        local rank = { HeaderTextBlock = 1, ReportContent = 2, ReportContent_1 = 3 }
        local kept = {}
        for i, p in ipairs(parts) do p.i = i kept[#kept + 1] = p end
        table.sort(kept, function(a, b)
            local ra, rb = rank[a.name] or 9, rank[b.name] or 9
            if ra ~= rb then return ra < rb end
            return a.i < b.i
        end)
        return without_buttons(kept, path)
    end,
    -- Its progress line ("Caching Shaders 67.61%") changes all the time and
    -- would read the screen again and again; only the story text is read.
    WBP_Loading_Screen_C = function(parts)
        local out = {}
        for _, p in ipairs(parts) do
            if not p.path:find("%.StepText$") then out[#out + 1] = p.text end
        end
        return table.concat(out, " ")
    end,
    WBP_EndOfGameMissionInfo_01_C = end_of_game,
    WBP_MultipleChoiceWidget_C = multiple_choice,
    WBP_AwayMissionDetailView_C = away_detail, WBP_BattleResultLCARS_C = battle_result,
    WBP_EnergyLossInfoWidget_C = energy_loss, WBP_ResearchInfoWidget_C = research_info,
    -- Read with the report above, which includes it.
    WBP_ResearchReport_C = function()
        if shown_widget("WBP_ResearchInfoWidget_C") then return "" end
        return research_rewards()
    end,
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
    -- A side mission's end: "Phage. CONTINUE. Mission Failed" had its
    -- button's label in the middle (VM, 2026-10-15). The button is said
    -- on its own after the window.
    -- With rewards the parts came in screen order: "250. Faces. XP. +5.
    -- Mission Successful" (Faces, VM, 2026-10-16). Now the title, the
    -- outcome, then each reward row as "250 XP" or "5 dilithium" (the
    -- resource is the row's Reward_Image).
    WBP_SideMissionFinished_C = function(parts, path)
        local head, outcome, other, seen = nil, nil, {}, {}
        for _, p in ipairs(parts) do
            local name = p.path:match("([^%.]+)$") or ""
            if not p.path:find("Button[%w_]*%.") and not p.path:find("WBP_PoIMultipleChoice_Reward_C", 1, true) and not seen[p.text] then
                seen[p.text] = true
                if name == "HeaderTextBlock" then head = p.text
                elseif name == "ContentTextBlock" then outcome = p.text
                else other[#other + 1] = (p.text:gsub("%.%s*$", "")) end
            end
        end
        local rewards = {}
        for _, r in ipairs(FindAllOf("WBP_PoIMultipleChoice_Reward_C") or {}) do
            if r:IsValid() and path and screen.inside(r, path) and screen.shown(r) then
                local function txt(w) local ok, s = pcall(function() return w:GetText():ToString() end); return ok and s or "" end
                local xp = ""
                pcall(function() if screen.shown(r.XPAmount_Text) then xp = txt(r.XPAmount_Text) end end)
                if xp ~= "" then
                    rewards[#rewards + 1] = xp:gsub("^%+", "") .. " experience"
                else
                    local amount = txt(r.RewardAmount_Text):gsub("^%+", "")
                    local icon = icon_name(r.Reward_Image)
                    local res = (icon and require("text").icon_name(icon)) or "resources"
                    if amount ~= "" then rewards[#rewards + 1] = amount .. " " .. res end
                end
            end
        end
        local out = {}
        if head then out[#out + 1] = head end
        if outcome then out[#out + 1] = outcome end
        for _, s in ipairs(other) do out[#out + 1] = s end
        if #rewards > 0 then out[#out + 1] = "Rewards: " .. table.concat(rewards, ", ") end
        for i, s in ipairs(out) do out[i] = (s:gsub("%.%s*$", "")) end
        return table.concat(out, ". ") .. "."
    end,
    WBP_RoomManagementV2_C = function(_, path) return require("rooms").window_text(path) end,
    WBP_AwayMissionLoadout_C = function() return require("awaymission").window_text() end,
    WBP_AwayMissionOutcome_C = function(_, path) return require("awaymission").outcome_text(path) end }
-- The main menu's Delete Profile warning has the same parts.
LAYOUTS.WBP_DeleteProfileWarning_C = LAYOUTS.WBP_PauseMenu_Confirms_C
-- A main mission's end (WBP_MissionInfoWidget): "Leaving the sector will
-- cause... Travel Now. Stay Here. State of Flux. Congratulations!..."
-- (VM, 2026-10-15). Mission name, title, message, then the warning; the
-- buttons are the list.
LAYOUTS.WBP_MissionInfoWidget_C = function(parts, path)
    local rank = { HeaderTextBlock_1 = 1, HeaderTextBlock_2 = 1, Title = 2, Content = 3, Description = 4, HeaderTextBlock = 5 }
    local kept = {}
    for i, p in ipairs(parts) do p.i = i kept[#kept + 1] = p end
    table.sort(kept, function(a, b)
        local ra, rb = rank[a.name] or 9, rank[b.name] or 9
        if ra ~= rb then return ra < rb end
        return a.i < b.i
    end)
    return without_buttons(kept, path)
end
for _, c in ipairs(SAVE_WARNINGS) do LAYOUTS[c] = LAYOUTS.WBP_PauseMenu_Confirms_C end

-- True while an event window's text has changed since it was last read:
-- the poll is about to read it and say the focused button after it. Focus
-- reached CONTINUE 80 ms before the result was read, and "CONTINUE" came
-- first (Abandoned Mining Station, VM, 2026-10-15).
function M.event_unread(button_path)
    local p = button_path and button_path:match("^(.-WBP_POIMultipleChoice_C_%d+)")
    if not (p and last_text[p]) then return false end
    local ok, text = pcall(M.text_under, p)
    return ok and text ~= last_text[p] and text:find("%a") ~= nil
end

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
    -- The Q Trials setup stays alive and "shown" behind a started trial:
    -- its 30 buttons became a list read over the loading screen and the
    -- game (Casey, 2026-10-14). With the game's HUD up it is not a window.
    local in_game = shown_widget("WBP_HUD_C") or shown_widget("WBP_Loading_Screen_C")
    -- A room window left open when the story switched to the System Map is
    -- still "shown" behind the map; it is not in front (rooms.lua).
    local okm, map = pcall(function() return require("system").active() end)
    local skip_room = okm and map
    for i, cls in ipairs(WATCH) do
        local skip = (in_game and cls == "WBP_Sandbox_Setup_C") or (skip_room and cls == "WBP_RoomManagementV2_C")
        for _, w in ipairs((not skip) and FindAllOf(cls) or {}) do
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
        -- A confirmation inside a window is read on its own (the away
        -- team's "You still have unassigned slots. Continue?" was silent,
        -- 2026-10-14).
        if nested and (p:find("WBP_AM_ConfirmStart_C", 1, true) or p:find("FewerHeroesConfirmWidget", 1, true)) then nested = false end
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

local settle = {}      -- path -> { text, at }: a window read once it stops changing

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
        -- The away mission summary fills in after it opens (only "Mission
        -- complete" was read, 2026-10-14).
        local reread = announced[p] and (p:find("WBP_POIMultipleChoice_C", 1, true)
            or p:find("WBP_OverviewInfoWidget_C", 1, true) or p:find("WBP_AwayMissionOutcome", 1, true)
            or p:find("WBP_Sandbox_Setup_C", 1, true) or rereading(p))
        if not announced[p] or reread then
            crumb.at("popups: read " .. p)
            local text = M.text_under(p)
            -- The start warning a slot's Enter raises is closed by focus.lua
            -- at once; reading it first was only noise (2026-10-14).
            local quiet = p:find("FewerHeroesConfirmWidget", 1, true)
                and os.clock() < (require("focus").quiet_start_warning_until or 0)
            -- The warning's buttons came first ("Continue. Return.
            -- Warning..."); they are in the button list, so leave them out.
            -- Battle toasts name a ship's side as the screen draws it
            -- ("Voyager Shield Down: Right"); L says bow, aft, port and
            -- starboard, so the toasts do too (VM, 2026-10-14).
            if p:find("Toast_Notification", 1, true) then
                local SIDES = { Right = "starboard", Left = "port", Front = "bow", Back = "aft", Rear = "aft" }
                text = text:gsub(":%s*(%a+)(%.?)$", function(w, dot)
                    return SIDES[w] and (": " .. SIDES[w] .. dot) or nil
                end)
                -- "Subsystem Destroyed: Weapons" did not say whose.
                local sys = text:match("Subsystem Destroyed:%s*([%a ]-)%.?$")
                local low = false
                if not sys then
                    sys = text:match("Subsystem HP low:%s*([%a ]-)%.?$")
                    low = sys ~= nil
                end
                local okw, owner = pcall(function() return sys and require("combat").destroyed_owner(sys, low) end)
                if okw and owner then text = text:gsub(":%s*" .. sys, ": " .. owner .. "'s " .. sys, 1) end
            end
            if p:find("FewerHeroesConfirmWidget", 1, true) then
                -- Also after the title: "Warning. Return. Continue. You
                -- still have unassigned slots" (battle setup, VM, 2026-10-16).
                text = text:gsub("Continue%. Return%. ", ""):gsub("Return%. Continue%. ", "")
                -- Sometimes only one of them: "Warning. Continue. You still
                -- have unassigned slots" (Q Trial, VM, 2026-10-16).
                text = text:gsub("^(Warning%.) Continue%. ", "%1 "):gsub("^(Warning%.) Return%. ", "%1 ")
                -- Or before the title: "Continue. Warning. You still..."
                -- (campaign battle, VM, 2026-10-16).
                text = text:gsub("^Continue%. (Warning%.)", "%1"):gsub("^Return%. (Warning%.)", "%1")
            end
            -- The away mission summary counts up as it fills in, and was
            -- read three times over (2026-10-14): it is read once its text
            -- has stayed the same for two seconds.
            local outcome = p:find("WBP_AwayMissionOutcome", 1, true) ~= nil
            local waiting = false
            if outcome then
                local s = settle[p]
                if not s or s.text ~= text then
                    settle[p] = { text = text, at = os.time() }
                    waiting = true
                elseif os.time() - s.at < 2 then
                    waiting = true
                end
            end
            -- A window with no words, only a number, said just "1" when the
            -- System Map opened (2026-10-11); it is skipped.
            if quiet then
                last_text[p] = text
            elseif waiting then
            elseif text:find("%a") and text ~= last_text[p] and not (reread and last_text[p] == nil and not outcome) then
                print("[VoyagerAccess] popup: " .. text .. " (" .. (p:match("([%w_]+)$") or "?") .. ")\n")
                -- A new event: its first option took focus and was spoken
                -- before the event's own text, so the option came first
                -- (2026-10-14). Interrupt it, then say the option again.
                -- Room windows too: "Repair" came before "Transporter Room".
                local first_event = not announced[p] and (p:find("WBP_POIMultipleChoice_C", 1, true)
                    or p:find("WBP_RoomManagementV2_C", 1, true) or p:find("WBP_ConstructionInfoWidget_C", 1, true)
                    or p:find("WBP_RadialMenu_C", 1, true) or p:find("WBP_EnergyLossInfoWidget_C", 1, true)
                    or p:find("WBP_MultipleChoiceWidget_C", 1, true) or p:find("WBP_PauseMenu_Confirms_C", 1, true)
                    or p:find("WBP_DeleteProfileWarning_C", 1, true) or p:find("WBP_GameOver_C", 1, true)
                    or p:find("WBP_NoWayBackWidget_C", 1, true) or p:find("WBP_CraftingResult_C", 1, true)
                    or p:find("WBP_ConfirmationWidget_C", 1, true) or p:find("WBP_HeroUnavailableWidget_C", 1, true)
                    or p:find("WBP_EngineeringOffice_Confirmation_C", 1, true) or p:find("WBP_CargoSwap_Confirmation_C", 1, true)
                    or p:find("WBP_Sandbox_Setup_C", 1, true) or p:find("WBP_LeaveSector_C", 1, true)
                    or p:find("WBP_SandboxSectorResult_C", 1, true) or is_save_warning(p)
                    -- Inside the combat widget it is named CombatResultView.
                    or p:find("WBP_BattleResultLCARS_C", 1, true) or p:find("CombatResultView", 1, true) or p:find("AutoResolveWidget", 1, true)
                    or p:find("WBP_FirstPerformanceSelection_C", 1, true) or p:find("WBP_GammaCorrection_C", 1, true))
                -- An event's result replaces its options in the same window:
                -- "CONTINUE" came before "Trading Station. We accepted their
                -- trade offer" (VM, 2026-10-14).
                    or (announced[p] and last_text[p] ~= nil and p:find("WBP_POIMultipleChoice_C", 1, true) ~= nil)
                -- The summary changes again after it was read, when a rank
                -- counts up: the whole summary came a second time with only
                -- "rank 1" now "rank 2" (demo, VM, 2026-10-15). Only the
                -- sentences that changed are said.
                local say = text
                if outcome and last_text[p] then
                    local old = {}
                    for s in (last_text[p] .. " "):gmatch("(.-%.)%s+") do old[s] = true end
                    local new = {}
                    for s in (text .. " "):gmatch("(.-%.)%s+") do
                        if not old[s] then new[#new + 1] = s end
                    end
                    if #new > 0 then say = table.concat(new, " ") end
                end
                -- Between an option and its result the event shows its
                -- description alone, and that was read again with CONTINUE
                -- before the result (Icy Planetoid, VM, 2026-10-15). A
                -- reread that only lost sentences says nothing.
                local nothing_new = false
                if reread and last_text[p] and p:find("WBP_POIMultipleChoice_C", 1, true) then
                    local old = {}
                    for s in (last_text[p] .. " "):gmatch("(.-%.)%s+") do old[s] = true end
                    nothing_new = true
                    for s in (text .. " "):gmatch("(.-%.)%s+") do
                        if not old[s] then nothing_new = false end
                    end
                end
                if nothing_new then
                    print("[VoyagerAccess] popup: only lost text, not read again (" .. (p:match("([%w_]+)$") or "?") .. ")\n")
                    -- Focus moves to CONTINUE before the result is in, and
                    -- "CONTINUE" came first (Abandoned Vessel, VM,
                    -- 2026-10-15); the result is read with the button after it.
                    -- Held until the result is read: focus moved about 3 s
                    -- after the choice once (Icy Planetoid), so 10 s is only
                    -- a safety limit.
                    -- Only while no options are left: a stage that keeps
                    -- options must let the focused one be said (review,
                    -- 2026-10-15).
                    local options_left = false
                    for _, ob in ipairs(FindAllOf("WBP_POISelectableOption_C") or {}) do
                        if ob:IsValid() and path_of(ob):find("^/Engine/Transient%.") and screen.shown(ob) then
                            options_left = true
                        end
                    end
                    M.result_pending_until = (not options_left) and (os.clock() + 10) or nil
                else
                M.result_pending_until = nil
                -- Tutorials are not cut off by the next window (speech.lua).
                if p:find("Tutorial", 1, true) then
                    speech.say_protected(say)
                else
                    speech.say_long(say, first_event and true or nil)
                end
                -- An offer that opened over the construction ring left focus
                -- on the ring behind it, and its options could not be reached
                -- (2026-10-14): focus its first option the player can take.
                if first_event and p:find("WBP_MultipleChoiceWidget_C", 1, true) then
                    pcall(function()
                        local best, best_i = nil, 1e9
                        for _, b in ipairs(FindAllOf("WBP_MultipleChoice_Button_C") or {}) do
                            if b:IsValid() and path_of(b):find("^/Engine/Transient%.") and screen.shown(b)
                                and b:GetIsEnabled() then
                                local i = 0
                                pcall(function() i = b:GetParent():GetChildIndex(b) end)
                                if i < best_i then best, best_i = b, i end
                            end
                        end
                        if best and not (best:HasKeyboardFocus() or best:HasFocusedDescendants()) then best:SetFocus() end
                    end)
                end
                -- The pause confirmation's buttons are the window list's,
                -- said by focus.lua once the window is read; asking here
                -- named the pause menu behind it ("MAIN MENU", 2026-10-14).
                -- A window read as the mod's own button list says its first
                -- button itself: "CLOSE, 1 of 1" came twice after a
                -- Construction Report (VM, 2026-10-15).
                local own_list = false
                pcall(function() own_list = require("focus").virtual_active() end)
                if first_event and not own_list and not p:find("WBP_PauseMenu_Confirms_C", 1, true)
                    and not p:find("WBP_DeleteProfileWarning_C", 1, true) and not p:find("WBP_Sandbox_Setup_C", 1, true)
                    and not is_save_warning(p) then
                    local function say_label()
                        local okl, label = pcall(function() return require("focus").current_label() end)
                        if okl and label and label ~= "" then speech.say(label, false) end
                    end
                    -- An event's options: the game's own chances are read
                    -- first (events.sweep), then the focused option is said.
                    if p:find("WBP_POIMultipleChoice_C", 1, true) then
                        local oks = pcall(require("events").sweep, say_label)
                        if not oks then say_label() end
                    else
                        say_label()
                    end
                end
                end
                spoken[#spoken + 1] = text
            end
            if not waiting then last_text[p] = text end
        end
    end
    local changed = false
    for p in pairs(now) do if not announced[p] then changed = true end end
    for p in pairs(announced) do if not now[p] then changed = true end end
    announced = now
    -- A window that closed is read afresh when it opens again: the battle
    -- setup's "unassigned slots" warning, closed quietly after a slot's
    -- Enter, kept its text and said only "Return" when it came up for real
    -- (VM, 2026-10-14).
    for p in pairs(last_text) do if not now[p] then last_text[p] = nil end end
    if changed then save_announced() end
    if #spoken > 0 then require("dialogue").remember(table.concat(spoken, ". ")) end
end

-- Windows built on a watched one: FindAllOf finds only the exact class, so
-- a subclass (WBP_Dialogue_Window_Intro, coverage report 2026-10-15) was
-- silent. Every few seconds the top-level widgets on screen are checked
-- once per class; one whose parent class is watched is watched too, with
-- its parent's layout (technique review, 2026-10-16).
local watched_set, checked = nil, {}
local function adopt_subclasses()
    if not watched_set then
        watched_set = {}
        for _, c in ipairs(WATCH) do watched_set[c] = true end
    end
    local lib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local uw = StaticFindObject("/Script/UMG.UserWidget")
    local pc = FindFirstOf("PlayerController")
    if not (lib and uw and pc and pc:IsValid()) then return end
    local found = {}
    lib:GetAllWidgetsOfClass(pc, found, uw, true)
    for _, e in pairs(found) do
        local w = e:get()
        if w and w:IsValid() then
            local cls = w:GetClass()
            local name = cls:GetFName():ToString()
            if not checked[name] and not watched_set[name] then
                checked[name] = true
                local s, d = cls:GetSuperStruct(), 0
                while s and s:IsValid() and d < 5 do
                    local sn = s:GetFName():ToString()
                    if watched_set[sn] then
                        WATCH[#WATCH + 1] = name
                        watched_set[name] = true
                        if LAYOUTS[sn] and not LAYOUTS[name] then LAYOUTS[name] = LAYOUTS[sn] end
                        print("[VoyagerAccess] popups: watching " .. name .. " as a kind of " .. sn .. "\n")
                        break
                    end
                    s, d = s:GetSuperStruct(), d + 1
                end
            end
        end
    end
end

function M.install()
    load_announced()
    LoopInGameThreadWithDelay(3000, function()
        local ok, err = pcall(adopt_subclasses)
        if not ok then print("[VoyagerAccess] popups adopt error: " .. tostring(err) .. "\n") end
    end)
    LoopInGameThreadWithDelay(INTERVAL_MS, function()
        local ok2, err = pcall(poll)
        if not ok2 then print("[VoyagerAccess] popups error: " .. tostring(err) .. "\n") end
    end)
end

return M
