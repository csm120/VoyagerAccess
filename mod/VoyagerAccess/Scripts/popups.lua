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

local LAYOUTS = { WBP_POIDetailView_C = poi_detail, WBP_POIMultipleChoice_C = poi_event,
    WBP_RoomManagementV2_C = function(_, path) return require("rooms").window_text(path) end }

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
        local reread = announced[p] and p:find("WBP_POIMultipleChoice_C", 1, true)
        if not announced[p] or reread then
            crumb.at("popups: read " .. p)
            local text = M.text_under(p)
            if text ~= "" and text ~= last_text[p] and not (reread and last_text[p] == nil) then
                print("[VoyagerAccess] popup: " .. text .. "\n")
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
