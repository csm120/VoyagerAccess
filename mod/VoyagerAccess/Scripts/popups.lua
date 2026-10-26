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
    -- Not WBP_PoiEventWidget_C: it is a point's marker on the map (PoiCircle,
    -- HarvestTimeRemaining_TXT in the dump), not a window. Watched since
    -- 0.1.0, it never said anything (no "popup:" line from it in any log;
    -- system.lua already treats it as no window), but each of the map's
    -- markers was read as a window on arriving at the System Map, 53 ms
    -- each, about 0.8 s in all (timing log, 2026-10-21 11:10:56).
    "WBP_AwayMissionEventView_C",
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
-- Read the windows whose path contains needle again on their next change,
-- even with the same text. A second scan reuses the open POIDetailView, so the
-- new planet's event and its item rewards were never read, only the rewards
-- as buttons (Casey, "Kazon Security Codes", 2026-10-14). system.lua calls
-- this on Scan.
-- Since the reads follow the game's events (0.3.68) nothing checked the
-- time this kept, and a second point whose details read the same as the
-- first (two asteroids) was silent after its scan (VM, 2026-10-21): the
-- windows are forgotten now, so the scan's update is read whatever it says.
-- Returns what was forgotten, for M.restore when the scan did not go
-- through (nothing changes then, and a later unrelated event would have
-- read the same details again; Fable review, 2026-10-21).
function M.reread_for(needle)
    return M.forget(needle)
end
-- Forgets what the windows whose path contains needle last said, so the
-- next poll reads them again: a tab switch back to the Overview's Heroes tab
-- said nothing, its text being the same as before (VM, 2026-10-17).
-- Returns { path = old text } for M.restore.
function M.forget(needle)
    local saved = {}
    for p, t in pairs(last_text) do
        -- Not nil: a re-read skips a window with nothing remembered.
        if p:find(needle, 1, true) then
            saved[p] = t
            last_text[p] = "\0"
        end
    end
    return saved
end
-- Puts back what M.forget returned, for windows not read since.
function M.restore(saved)
    for p, t in pairs(saved or {}) do
        if last_text[p] == "\0" then last_text[p] = t end
    end
end
-- What the first window whose path contains needle last said, or nil.
function M.remembered(needle)
    for p, t in pairs(last_text) do
        if p:find(needle, 1, true) then return t end
    end
    return nil
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

M.plain = plain

-- read_stop: a window the game has just activated while a parent is still
-- fading in; its texts count as shown when shown inside it (set by
-- process below for the read of that window only).
local read_stop = nil
-- False while popups' read of a window may still be retried (process below);
-- true otherwise, including every read from outside process.
local read_last_try = true
-- The search parts_under used until 2026-10-21, kept for the development
-- comparison below: every text in the game whose path is under the window,
-- in creation order. It took 60 to 120 ms a window (timing log).
local function search_parts(path)
    local prefix = path .. "."
    local parts, seen_obj = {}, {}
    for _, cls in ipairs(TEXT_CLASSES) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            if t:IsValid() then
                local tp = path_of(t)
                if tp and not seen_obj[tp] and tp:sub(1, #prefix) == prefix and screen.shown(t, read_stop) then
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

-- Development only (flag file "treecheck"): each window read is also read
-- by the old search and both are timed; a window class whose spoken text
-- differs is logged once per difference.
local TREECHECK = (function()
    local f = io.open((os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\treecheck", "r")
    if f then f:close() return true end
    return false
end)()
local tree_logged = {}
-- On-screen texts inside the widget at path, as { name = last part of the
-- text widget's name, text = plain text, path }, in the order of the
-- window's own widget tree (its layout), found by walking that tree rather
-- than searching every text in the game: a few ms a window where the search
-- took 60 to 200 ms, compared window by window in the VM (flag "treecheck",
-- 2026-10-21). Only TextBlocks and RichTextBlocks (and their subclasses)
-- are read, as the search did: GetText on an EditableText crashes the game
-- (see TEXT_CLASSES).
local TEXT_BASES = nil
local function is_text(w)
    TEXT_BASES = TEXT_BASES or { StaticFindObject("/Script/UMG.TextBlock"), StaticFindObject("/Script/UMG.RichTextBlock") }
    for _, c in ipairs(TEXT_BASES) do
        if c and c:IsValid() and w:IsA(c) then return true end
    end
    return false
end
local function tree_parts(path)
    local root = StaticFindObject(path)
    local parts = {}
    if not (root and root:IsValid()) then return parts end
    -- read_stop is the window itself while a parent fades in: then only
    -- what is shown inside it counts.
    local inside = read_stop ~= nil and read_stop:GetFullName() == root:GetFullName()
    if not inside and not screen.shown(root, read_stop) then return parts end
    -- The window itself not visible yet (activated while it fades in): the
    -- old search reads its texts without walking its children, since
    -- walking a hidden panel's children once crashed the game (probe,
    -- 2026-10-20; Fable review, 2026-10-21).
    -- The search's order is the order the game made the texts in, so the
    -- same card read "Chakotay. Homesick." while fading in and "Homesick.
    -- Chakotay." after (VM, 2026-10-21). Nothing is read until the window
    -- is visible, through popups' retries (up to about 2 s); the search is
    -- the last try only.
    if inside and not root:IsVisible() then
        if not read_last_try then return parts end
        return search_parts(path)
    end
    -- Only texts whose path is under the window, as the search had it: the
    -- build ring's centre texts belong to the game instance, and read with
    -- the ring they said "Clear Debris. No Life Support. +16. +6." before
    -- the ring's own reading (VM, 2026-10-21).
    local prefix = path .. "."
    -- The battle setup's "unassigned slots" warning: its button labels are
    -- in the window's button list, and read with the message they came
    -- after it ("... Continue? Continue"). They were taken out by their
    -- English words, so in every other language they stayed (review of
    -- 0.3.70, 2026-10-22). Its buttons' branches are skipped instead, by
    -- class, in any language.
    local BTN = path:find("FewerHeroesConfirmWidget", 1, true) and StaticFindObject("/Script/CommonUI.CommonButtonBase")
    screen.walk(root, function(w)
        if BTN and BTN:IsValid() and w:IsA(BTN) then return true end
        if not is_text(w) then return false end
        local tp = path_of(w)
        if tp and tp:sub(1, #prefix) == prefix then
            local ok, s = pcall(function() return w:GetText():ToString() end)
            s = ok and plain(s) or ""
            local in_close = tp:find("%.Close[%w_]*Button[%w_]*%.") or tp:find("%.EnterShip[%w_]*%.")
            if s ~= "" and s:sub(1, 1) ~= "#" and not NOISE[s:upper()] and not in_close then
                parts[#parts + 1] = { name = tp:match("([^%.]+)$"), text = s, path = tp }
            end
        end
        return true
    end, { no_root_check = inside })
    return parts
end

local tree_stats = {}   -- class -> { same = n, differs = n }
local function tree_compare(path, tp, tree_ms)
    local w = StaticFindObject(path)
    local cls = (w and w:IsValid()) and w:GetClass():GetFName():ToString() or "?"
    local t0 = os.clock()
    local parts = search_parts(path)
    local search_ms = math.floor((os.clock() - t0) * 1000 + 0.5)
    -- The search first: a layout can remember what it read (poi_detail),
    -- and the tree's reading is the one the mod goes on with.
    local sa = M.text_from(parts, path)
    local sb = M.text_from(tp, path)
    local st = tree_stats[cls] or { same = 0, differs = 0 }
    tree_stats[cls] = st
    local verdict
    if sa == sb then
        st.same = st.same + 1
        verdict = "same"
    else
        st.differs = st.differs + 1
        local na, nb = {}, {}
        for _, p in ipairs(parts) do na[#na + 1] = p.name end
        for _, p in ipairs(tp) do nb[#nb + 1] = p.name end
        verdict = "DIFFERS: search [" .. sa .. "] tree [" .. sb .. "] names search " .. table.concat(na, ",")
            .. " tree " .. table.concat(nb, ",")
    end
    local key = cls .. verdict
    if tree_logged[key] then return end
    tree_logged[key] = true
    print(string.format("[VoyagerAccess] treecheck: %s search %d ms tree %d ms (same %d, differs %d), %s\n",
        cls, search_ms, tree_ms, st.same, st.differs, verdict))
end

local function parts_under(path)
    local t0 = os.clock()
    local parts = tree_parts(path)
    if TREECHECK then
        local ms = math.floor((os.clock() - t0) * 1000 + 0.5)
        pcall(tree_compare, path, parts, ms)
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
    -- Each reward's name and amount are paired by the entry widget they sit
    -- in, not by which comes first: read in widget-tree order the name came
    -- before its amount and "amount unknown" was lost (VM, 2026-10-21).
    local rewards, entries, order = {}, {}, {}
    for _, p in ipairs(parts) do
        if p.name == "ResourceAmountTextBlock" or p.name == "ResourceNameTextBlock" then
            -- The tree the text sits in: its path without the last part.
            -- Live trees are numbered ("WidgetTree_2147..."); a pattern for
            -- ".WidgetTree." never matched, and every amount was dropped
            -- (GPT review; "Resources: Duranium" with no amount, VM,
            -- 2026-10-21).
            local owner = (p.path or ""):match("^(.*)%.[^%.]+$") or p.path or ""
            local e = entries[owner]
            if not e or (e[p.name] ~= nil) then
                e = {}
                entries[owner] = e
                order[#order + 1] = e
            end
            e[p.name] = p.text
        end
    end
    for _, e in ipairs(order) do
        if e.ResourceNameTextBlock then
            local a = e.ResourceAmountTextBlock
            local amount = a and (a == "unknown" and (", amount unknown" .. until_text)
                or (", amount " .. a)) or ""
            rewards[#rewards + 1] = e.ResourceNameTextBlock .. amount
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
    -- The ambush line ("Chance of ambush", "No chance of ambush" in the
    -- game's General texts), shown under the rewards once Threat Assessment
    -- Sensors are researched. It is AmbushText in the resource event view
    -- (WBP_ResourceEventDetailView, collapsed AmbushContainer by default);
    -- the scan plaque (WBP_ScanPlaqueEventView) is handed bShowAmbush and
    -- bHasAmbush but has no element that shows them (widget and header
    -- dumps, 2026-10-24). Only when shown (tree_parts reads shown texts),
    -- and never the designer's placeholder "Ambush.......".
    local ambush = by.AmbushText
    if ambush and ambush:find("^Ambush%.%.") then ambush = nil end
    if ambush then out[#out + 1] = ambush end
    if by.UpgradeText and not upgrade then out[#out + 1] = by.UpgradeText end
    -- Anything else the window shows, after the known parts.
    local known = { LocationNameTextBlock = true, SystemNameTextBlock = true, System_TextBLock = true,
        ResourceEventNameTextBlock = true, UpgradeText = true, AmbushText = true }
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
    -- The ambush line too, as when it was read with the extras.
    if ambush then names[#names + 1] = ambush end
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
    out[#out + 1] = "Outcome: " .. require("tr").lower(by.ResultOutcome_Text)
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
            if level ~= "" then entry[#entry + 1] = require("tr").lower(level) end
            local ls = text_of_widget(w.LifeSupport)
            if ls ~= "" then entry[#entry + 1] = require("tr").lower(ls) end
            local crew = text_of_widget(w.CrewValueNew)
            if crew ~= "" then entry[#entry + 1] = require("tr").fill("crew {s}", crew) end
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
    if by.CrewValue then totals[#totals + 1] = require("tr").fill("crew {s}", by.CrewValue) end
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
    if require("hints").fresh("report_close") then
        out[#out + 1] = "Close finishes all actions, activates the rooms and collects resources"
            .. (other and "; Enter Ship lets you manage it yourself" or "")
    end
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- Texts of a window in screen order: a walk of its widget tree, which is
-- the order they are laid out in (FindAllOf gives creation order, which
-- came out jumbled more than once). Hidden widgets and buttons' own labels
-- are left out; skip(name, text) returns true to drop a text, or a string
-- to say instead.
-- Visibility is followed on the way down (screen.walk), not worked out
-- from the top for every widget: the Overview's read held the game for
-- about 400 ms that way (timing log, 2026-10-21). Only text widgets are
-- asked for their text (is_text): GetText on an EditableText crashes.
local function ordered_texts(root, skip)
    local BTN = StaticFindObject("/Script/CommonUI.CommonButtonBase")
    local out = {}
    if not (root and root:IsValid() and screen.shown(root)) then return out end
    screen.walk(root, function(w)
        if w:IsA(BTN) then return true end
        if not is_text(w) then return false end
        local ok, txt = pcall(function() return w:GetText():ToString() end)
        if ok and type(txt) == "string" then
            local t = plain(txt)
            local name = w:GetFName():ToString()
            if t ~= "" and skip then
                -- The raw text too, line breaks and all, for a reader that
                -- needs them (energy_loss).
                local keep = skip(name, t, txt)
                if type(keep) == "string" then t = keep elseif keep then t = "" end
            end
            if t ~= "" then out[#out + 1] = t end
        end
        return true
    end, { no_lists = true })
    return out
end

-- Joins texts into sentences, putting numbers with the label before them:
-- "Available Energy", "78", "120" -> "Available Energy 78 of 120".
local function number_lines(texts)
    local out, run = {}, 0
    for _, t in ipairs(texts) do
        local number = t:match("^[%+%-]?[%d,%.]+%%?$") or t:match("^%(?[%d,]+ %- [%d,]+%)?$")
        if number and #out > 0 then
            run = run + 1
            out[#out] = out[#out] .. (run == 2 and require("tr").word(" of ") or " ") .. t
        else
            run = 0
            out[#out + 1] = t
        end
    end
    -- A range's closing bracket is its own text and dropped, which left
    -- "Low Morale (0 - 800" (VM, 2026-10-15): "Low Morale 0 to 800".
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", ""):gsub("%(([%d,]+) %- ([%d,]+)%)?", "%1 to %2") end
    -- A line break inside one text ends a heading: "ASTEROID FIELD" then
    -- "Entering an asteroid field" ran together when said (Sensor Alert,
    -- WBP_CommonInfoWidget, VM, 2026-10-17).
    -- Only before a line that starts a sentence: capitals wrapped onto two
    -- lines stay one label (text.lua).
    for i, s in ipairs(out) do out[i] = (s:gsub("([^%.!%?:;,%s])[ \t]*\r?\n[\r\n%s]*(%u%l)", "%1. %2")) end
    return out
end

local function join_numbers(texts)
    return table.concat(number_lines(texts), ". ") .. "."
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

-- The tab as lines (the Up and Down list), or nil and the reading for the
-- Heroes tab, which has its own list of heroes.
local function overview_lines(path)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return {} end
    local tab, tab_id = nil, ""
    for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
        local p = b:IsValid() and path_of(b)
        if p and p:sub(1, #path + 1) == path .. "." and p:find("_Tab_Button$") and screen.shown(b) then
            local ok, sel = pcall(function() return b:GetSelected() end)
            if ok and sel then
                local okt, t = pcall(function() return b.Button_Text:GetText():ToString() end)
                tab = okt and t or nil
                -- Which tab by the button's own name (Hero_Tab_Button,
                -- Combat_Tab_Button): the text is translated, and in French
                -- the Heroes tab was read whole (VM, 2026-10-17).
                tab_id = p:match("([%w]+)_Tab_Button$") or ""
            end
        end
    end
    -- The Heroes tab is walked hero by hero (view.lua); read whole, its
    -- ranks came out beside the wrong names and every selection read the
    -- whole tab again (VM, 2026-10-15).
    if tab and tab_id == "Hero" then
        local n = 0
        pcall(function() n = require("view").hero_count() end)
        return nil, "Overview, " .. tab .. " tab. " .. n .. " heroes" .. require("hints").text("ov_heroes", ". Up and Down choose one and read its details") .. "."
    end
    -- The Combat tab is two tables (rooms, how many, their combat power)
    -- and a sum; read as a flat list it came out "combat power 0 of 12 ...
    -- Hull 0.112 of 400" (VM, 2026-10-15).
    if tab and tab_id == "Combat" then
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
                return rows
            end
            local def, off = table_at("col_defense"), table_at("col_Offense")
            out[#out + 1] = "Overview, " .. tab .. " tab"
            -- Each room row its own item in the list (VM, 2026-10-19).
            local function add_table(head, rows)
                if not rows then return end
                out[#out + 1] = head
                for _, r in ipairs(rows) do out[#out + 1] = r end
            end
            add_table("Defense", def)
            add_table("Offense", off)
            if by.TECH_PWR then out[#out + 1] = "Tech combat power " .. by.TECH_PWR end
            if by.HULL_PWR then out[#out + 1] = "Defensive combat power " .. (by.Def_PWR or by.HULL_PWR) .. ", from hull " .. by.HULL_PWR end
            if by.OFF_PWR then out[#out + 1] = "Offensive combat power " .. by.OFF_PWR .. (by.BATT_PWR and (", base attack power " .. by.BATT_PWR) or "") end
            if by.WarpCoreTier then out[#out + 1] = "Warp core " .. require("tr").lower(by.WarpCoreTier) end
            if by.ReqCE_Value then out[#out + 1] = "Required combat energy " .. by.ReqCE_Value:gsub("/", " of ") end
            if by.reduction then out[#out + 1] = "Combat power lost to missing energy " .. by.reduction end
            if by.ACP then out[#out + 1] = "Combat ally " .. by.ACP end
            if by.TCP then out[#out + 1] = "Voyager combat power " .. by.TCP .. (by.avgNmyPwr and (", against average enemy power " .. by.avgNmyPwr) or "") end
            return out
        end
    end
    local level = nil   -- Heroes tab: "Lv. 1" comes before the name it belongs to
    -- Warp Core tab: "+" (BonusSign) and "12" (EnergyBonusPerCycleText_1)
    -- with an energy icon beside the output, read as a bare "It produces
    -- 120 energy 12" (VM, 2026-10-19).
    local bonus_sign = "+"
    local texts = ordered_texts(w, function(name, t)
        if name == "BonusSign" then
            bonus_sign = t
            return true
        end
        if name == "EnergyBonusPerCycleText_1" then
            return (bonus_sign == "-" and "minus " or "plus ") .. t:gsub("^[%+%-]", "") .. " energy bonus"
        end
        if OVERVIEW_LABELS[name] then
            -- "uses -24 deuterium": the sign is in "uses" already.
            local v = t:gsub("^%+", ""):gsub("/$", "")
            if name == "ConsumedDeuteriumText" then v = v:gsub("^%-", "") end
            -- A Morale row's crew and max morale are marked by their widget
            -- (\1, \2) for the grouping below: matching the words "crew"
            -- and "max morale" failed once "crew" was said in the game's
            -- language (firefly82's review, 2026-10-20: rows by widget, not
            -- by text).
            if OVERVIEW_LABELS[name] == "%s crew" then return "\1" .. require("tr").fill("{s} crew", v) end
            if OVERVIEW_LABELS[name] == "max morale %s" then return "\2" .. string.format(OVERVIEW_LABELS[name], v) end
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
    -- One item per row as the screen sets it out (Morale tab, VM,
    -- 2026-10-19): a condition's crew, name and max morale ("79 crew,
    -- Without Quarters, max morale -1,200") were three items, and each
    -- threshold's effects ("-10% on all hero attributes") stood apart from it.
    local lines, out = number_lines(kept), {}
    local i = 1
    while i <= #lines do
        local l = lines[i]
        if l:sub(1, 1) == "\1" and lines[i + 2] and lines[i + 2]:sub(1, 1) == "\2" then
            out[#out + 1] = l:sub(2) .. ", " .. lines[i + 1] .. ", " .. lines[i + 2]:sub(2)
            i = i + 3
        elseif l:match("^[%+%-]%d+%%") and #out > 1 then
            out[#out] = out[#out] .. (out[#out]:match("%d$") and ": " or ", ") .. l
            i = i + 1
        else
            out[#out + 1] = (l:gsub("^[\1\2]", ""))
            i = i + 1
        end
    end
    return out
end

local function overview(_, path)
    local lines, said = overview_lines(path)
    if said then return said end
    if #lines == 0 then return "" end
    return table.concat(lines, ". ") .. "."
end

-- The shown Overview's tab as lines for view.lua's list (firefly82's review,
-- 2026-10-19: each tab was one long reading, and finding one number meant
-- hearing it all again), or nil when no Overview is shown or the tab has a
-- list of its own (Heroes).
function M.overview_lines()
    for _, x in ipairs(FindAllOf("WBP_OverviewInfoWidget_C") or {}) do
        if x:IsValid() and x:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(x) then
            local lines = overview_lines(path_of(x))
            return lines
        end
    end
    return nil
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
    if tabs > 1 then out[#out + 1] = (cur and require("tr").fill("{s} tab", cur) or require("tr").word("Tab")) .. ", Left and Right switch logs" end
    -- The body is not spoken: the game plays the officer reading the log
    -- (Casey, 2026-10-15, "the personal log has audio").
    for i, s in ipairs(out) do out[i] = s:gsub("%.%s*$", "") end
    return table.concat(out, ". ") .. "."
end

-- Left and Right on an open multitab log. True when handled.
-- The log is the shown one of the windows popups records (open_of), and the
-- tab is switched by the log's own RequestPreviousTab/RequestNextTab
-- (USTVLogEventWidget, header dump), not by searching every button in the
-- game for its Previous/NextTabButton. The new tab is read when the game
-- reports it, OnTabSelected (the same class's event), not 300 ms later.
local log_tab_hooked = {}   -- class path -> hooked (true/false)
local log_tab_wait = nil    -- { path, key }: the log whose tab the player switched, until the next key
local function say_log(wp)
    local t = log_multitab(nil, wp)
    last_text[wp] = t
    speech.say_long(t, true)
end
local function hook_log_tab(w)
    local cp = path_of(w:GetClass())
    if log_tab_hooked[cp] ~= nil then return log_tab_hooked[cp] end
    local fp = cp .. ":OnTabSelected"
    local ok = false
    if StaticFindObject(fp) then
        ok = pcall(RegisterHook, fp, function(ctx)
            local okp, p = pcall(function() return path_of(ctx:get()) end)
            if not okp then return end
            -- A pre hook: the tab is shown on the next tick.
            ExecuteInGameThread(function()
                local lw = log_tab_wait
                if not (lw and lw.path == p) then return end
                log_tab_wait = nil
                if require("keys").key_count ~= lw.key then return end
                pcall(say_log, p)
            end)
        end)
    end
    log_tab_hooked[cp] = ok
    print("[VoyagerAccess] popups: log tab event " .. (ok and "hooked" or "not hooked") .. "\n")
    return ok
end
function M.log_tab(dir)
    local w, wp = M.open_of({ WBP_LogEventWidget_Multitab_C = true })
    if not w then return false end
    local hooked = hook_log_tab(w)
    local mine = { path = wp, key = require("keys").key_count }
    log_tab_wait = hooked and mine or nil
    local ok = pcall(function()
        if dir < 0 then w:RequestPreviousTab() else w:RequestNextTab() end
    end)
    if not ok then
        log_tab_wait = nil
        print("[VoyagerAccess] popups: log tab switch failed\n")
        return true
    end
    -- Without the event: read after 300 ms as before, and the log says so.
    if not hooked then
        print("[VoyagerAccess] popups: log tab read without its event\n")
        ExecuteInGameThreadWithDelay(300, function()
            if require("keys").key_count == mine.key then pcall(say_log, wp) end
        end)
        return true
    end
    -- The bounded fallback behind the event: none in 600 ms, read then.
    ExecuteInGameThreadWithDelay(600, function()
        if log_tab_wait ~= mine then return end
        log_tab_wait = nil
        if require("keys").key_count ~= mine.key then return end
        print("[VoyagerAccess] popups: no log tab event in 600 ms, read now\n")
        pcall(say_log, wp)
    end)
    return true
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
    if by.Voyager_Hull then out[#out + 1] = require("tr").fill("Hull {s}", by.Voyager_Hull) end
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
        out[#out + 1] = kind .. ": " .. by.TechName .. (by.NewText and require("tr").word(", new") or "")
        local where = {}
        if by.TechTreeName then where[#where + 1] = by.TechTreeName end
        if by.TierNr_TXT then where[#where + 1] = (by.TierNr_TXT:gsub("0(%d)", "%1")) end
        if #where > 0 then out[#out + 1] = table.concat(where, ", ") end
        if by.TechDesc then out[#out + 1] = by.TechDesc end
    elseif by.HeroName_TXT then
        local head = kind .. ": " .. by.HeroName_TXT
        if by.HeroLevel_TXT then head = head .. ", " .. require("tr").lower((by.HeroLevel_TXT:gsub("0(%d)", "%1"))) end
        if by.TraitText then head = head .. ", " .. by.TraitText end
        out[#out + 1] = head
        local skills = ""
        pcall(function() skills = require("rooms").skills_of(card.HeroStatSheet) end)
        if skills ~= "" then out[#out + 1] = skills end
        if by.HeroCombatAbility_TXT then out[#out + 1] = "Combat ability: " .. by.HeroCombatAbility_TXT end
    elseif by.AmusementName then
        -- A Q Modifier card: its name and what it does ("Party Ship" was
        -- read only as "Q Modifier", VM, 2026-10-16).
        out[#out + 1] = kind .. ": " .. by.AmusementName .. (by.NewText and require("tr").word(", new") or "")
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
    -- A second page of rewards ("Select a Q Modifier", after the first
    -- pick) came with no word that the page had changed: the first card
    -- was read alone (Q Trial, VM, 2026-10-18). Its heading is said once
    -- each time it changes.
    pcall(function()
        for _, w in ipairs(FindAllOf("WBP_SandboxSectorResult_C") or {}) do
            if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
                local head = text_of_widget(w.RewardHeadText)
                -- A new results window reads its first heading itself.
                if M.meta_window ~= path_of(w) then M.meta_window, M.meta_head_said = path_of(w), head end
                if head ~= "" and head ~= M.meta_head_said then
                    table.insert(out, 1, head .. ", " .. M.meta_reward_count())
                    M.meta_head_said = head
                end
            end
        end
    end)
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
    ["Transporter Room"] = "on the away team screen, Up and Down move between the slots and Enter chooses a hero; once every slot is filled, End moves to Start Mission and Enter starts it",
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
    -- Superseded 2026-10-24: the reason's lines were told apart by a capital
    -- after a lowercase word, which in German also split its nouns:
    -- "Deuterium erschöpft. Modus. Grau wird aktiviert" (firefly82,
    -- 2026-10-23). Its real line breaks are used instead, from the raw text:
    -- each line is a sentence.
    local t = ordered_texts(w, function(name, s, raw)
        if name == "EnergyLossReason" then
            if type(raw) ~= "string" or not raw:find("\n", 1, true) then
                -- No line break to go by: the old rule, in English only,
                -- where nouns are not capitalized ("Warp Core" kept whole).
                if not require("language").english() then return false end
                return (s:gsub("(%l) (%u%l*)", function(a, word)
                    if require("text").name_tail(word) then return a .. " " .. word end
                    return a .. ". " .. word
                end))
            end
            local lines = {}
            for line in (raw .. "\n"):gmatch("(.-)\r?\n") do
                local p = plain(line)
                if p ~= "" then lines[#lines + 1] = (p:gsub("%.%s*$", "")) end
            end
            return #lines > 0 and table.concat(lines, ". ") or false
        end
        -- The shared clean-up (text.lua) may already have named the icon:
        -- "9 energy energy" (VM, 2026-10-15). The game's own word for energy,
        -- and a word said twice after the number goes: German read "6
        -- Energie Energie" (firefly82, 2026-10-23).
        if name == "RoomsLost" then
            local word = require("text").game_resource_name("Energy") or "energy"
            local out = s:gsub(" %-%s*(%d+)", function(n) return " " .. n .. " " .. word end)
            out = out:gsub("(%d) ([^%s,%.]+) ([^%s,%.]+)", function(n, a, b)
                if a:lower() == b:lower() then return n .. " " .. a end
            end)
            return out
        end
        -- A label wrapped onto two lines is one label: "Max. aktivierbare.
        -- War..." (firefly82, 2026-10-23), the shared clean-up having taken
        -- the break for a new sentence. Only texts without a number, so a
        -- list of rooms with their energy keeps its commas.
        if type(raw) == "string" and raw:find("\n", 1, true) and not raw:find("%d") then
            local joined = plain((raw:gsub("%s*\r?\n%s*", " ")))
            if joined ~= "" then return joined end
        end
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
local none_word = nil   -- the game's "None" in its language, once seen
-- The lists as data, before the window draws them: SetDamageSummary on the
-- result window (firefly82's review, 2026-10-19). An empty array is "none"
-- in every language, with no word to recognise. Counts, or nil until a
-- battle has ended since the mod started.
local damage = nil
local DAMAGE_HOOK = "/Game/CombatPrototype/Blueprints/UI/WBP_BattleResultLCARS.WBP_BattleResultLCARS_C:SetDamageSummary"
local damage_hooked = false
function M.ensure_damage_hook()
    if damage_hooked or not StaticFindObject(DAMAGE_HOOK) then return end
    damage_hooked = pcall(RegisterHook, DAMAGE_HOOK, function(_, summary)
        pcall(function()
            local s = summary:get()
            damage = { injured = #s.InjuredCrewMembers + #s.InjuredHeroes, rooms = #s.DamagedRooms }
            print("[VoyagerAccess] battle: injured " .. damage.injured .. ", damaged rooms " .. damage.rooms .. "\n")
        end)
        -- The result window has no event of its own ("events: none"), and
        -- focus is looked at only after input: a battle that ended by
        -- itself left its result unsaid until a key (demo, VM, 2026-10-22:
        -- six minutes of silence). This call fills it, so the window and
        -- the focus are looked at now and as it fades in (request_settle).
        ExecuteInGameThread(function()
            pcall(M.reread_class, "WBP_BattleResultLCARS_C")
            pcall(function() require("focus").request_settle() end)
        end)
    end)
end
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
            -- Experience too: "Experience, 127" was two list items (Q
            -- Trial battle, VM, 2026-10-18).
            if name == "Experience_Text" then name = "ResourceNameTextBlock" end
            if name == "Experience_Amount" then name = "ResourceAmountTextBlock" end
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
            elseif name == "Win_Text" then outcome = "victory, " .. require("tr").lower(t)
            elseif name == "Lose_Text" then outcome = "defeat, " .. require("tr").lower(t)
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
    -- The game's word for an empty list is translated: the German game said
    -- "Injuries, 1: K/A" (firefly82, 2026-10-18). Both lists show it as
    -- one plain list item (BattleResultListViewItem, like any name), so it is
    -- learned when Injuries and Damaged rooms show the same single entry.
    local inj, rooms = lists["Injuries"], lists["Damaged rooms"]
    if inj and rooms and #inj == 1 and #rooms == 1 and inj[1] == rooms[1] then none_word = inj[1]:lower() end
    local function is_none(t) t = t:lower() return t == "none" or t == none_word end
    local function empty(s)
        if not damage then return nil end
        if s == "Injuries" then return damage.injured == 0 end
        if s == "Damaged rooms" then return damage.rooms == 0 end
        return nil
    end
    local out = { "Combat result: " .. (outcome or require("tr").word("over")) }
    if hull then out[#out + 1] = "Hull status " .. hull .. "%" end
    for _, s in ipairs(order) do
        -- With a count first: 22 injured names came with no hint of how many
        -- (Q Trial defeat, VM, 2026-10-14). "None" stays as it is.
        local n = #lists[s]
        local counted = s == "Injuries" or s == "Damaged rooms"
        local e = empty(s)
        if n == 1 and (e == true or (e == nil and is_none(lists[s][1]))) then out[#out + 1] = s .. ": none"
        elseif n > 0 and s == "Damaged rooms" then
            -- Two rooms of one type were said apart: "Life Support,
            -- Stellar Cartography, Life Support" (VM, 2026-10-17).
            local names, seen = {}, {}
            for _, r in ipairs(lists[s]) do
                if not seen[r] then seen[r] = 0; names[#names + 1] = r end
                seen[r] = seen[r] + 1
            end
            for i, r in ipairs(names) do if seen[r] > 1 then names[i] = r .. " times " .. seen[r] end end
            out[#out + 1] = s .. ", " .. n .. ": " .. table.concat(names, ", ")
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
    -- Said the Starfleet way, as on the map ("system 8 oh 1 6 point 3"):
    -- "system 8,016.3" read as a number (Friendship One, VM, 2026-10-21).
    if system and system ~= "" then
        local ok, spoken = pcall(function() return require("system").spoken_number(system) end)
        out[#out + 1] = "system " .. ((ok and spoken) or system)
    end
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
local function leave_sector(parts, path)
    -- Its Cancel is drawn as a button but not focusable, so the arrows never
    -- reached it while the list counted it ("2 of 3", then nothing; Q
    -- Trial, VM, 2026-10-18). A sighted player can click it.
    pcall(function()
        for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
            local bp = b:IsValid() and b:GetFullName():match("^%S+%s+(.+)$")
            if bp and bp:sub(1, #path + 1) == path .. "." and bp:find("%.CancelButton$") and not b:GetIsFocusable() then
                b:SetIsFocusable(true)
            end
        end
    end)
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
    local out = { require("tr").fill("Use {s}", t(b.ItemName_TXT) ~= "" and t(b.ItemName_TXT) or "bonus fuel") }
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

-- Up and Down in Leave Sector, done by the mod: with one sector offered the
-- game's own Down never left it, so Stay for now (its Cancel) could not be
-- reached, in 0.3.67 as well (Q Trial, VM, 2026-10-21; the 2026-10-18 fix
-- covered three sectors). The sectors in their order, then Stay for now.
-- True when the key was taken.
function M.leave_sector_step(current, dir)
    local win = current and current:match("^(.-WBP_LeaveSector_C_%d+)")
    if not win then return false end
    -- The window's own buttons, from its widget tree in layout order (the
    -- sectors as laid out), not a search of every button in the game.
    local entries, cancel = {}, nil
    local root = StaticFindObject(win)
    local BTN = StaticFindObject("/Script/CommonUI.CommonButtonBase")
    if not (root and root:IsValid() and BTN and BTN:IsValid() and screen.shown(root)) then return false end
    screen.walk(root, function(b)
        if not b:IsA(BTN) then return false end
        local p = path_of(b)
        if p and p:sub(1, #win + 1) == win .. "." then
            if p:find("WBP_LeaveSectorEntry_C_%d+$") then
                entries[#entries + 1] = { b = b, p = p }
            elseif p:find("%.CancelButton$") then
                cancel = { b = b, p = p }
            end
        end
        return true
    end)
    if cancel then entries[#entries + 1] = cancel end
    if #entries == 0 then return false end
    -- Focus on something else in the window: Down goes to the first entry.
    local at = 0
    for i, e in ipairs(entries) do if e.p == current then at = i end end
    local to = math.max(1, math.min(#entries, at + dir))
    if to == at then
        pcall(function() require("focus").reannounce() end)
    else
        pcall(function()
            entries[to].b:SetIsFocusable(true)
            entries[to].b:SetFocus()
        end)
        -- The game's selected exit follows its own navigation, not this
        -- focus: it stayed on Sector 02 while Sector 01 was heard (VM,
        -- 2026-10-22). Stay for now has no selection.
        if entries[to] ~= cancel then pcall(function() entries[to].b:NotifySelected() end) end
    end
    return true
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
        if by[pair[2]] then
            stats[#stats + 1] = pair[1] == "Time" and require("tr").fill("Time {s}", by[pair[2]]) or (pair[1] .. " " .. by[pair[2]])
        end
    end
    if #stats > 0 then out[#out + 1] = "Sector performance: " .. table.concat(stats, ", ") end
    if by.RemainingDistance_TXT then
        local total = (by.InitialDistance_TXT or ""):gsub("^%s*/%s*", "")
        out[#out + 1] = "Earth distance remaining " .. by.RemainingDistance_TXT .. (total ~= "" and (" of " .. total) or "")
    end
    local function nums(s) return (s:gsub("[()]", ""):gsub("%d+", function(d) return tostring(tonumber(d)) end)) end
    -- After a Game Over the rewards are only unlocked, and this read
    -- "Select a reward, 0 of 0" (Q Trial, VM, 2026-10-16).
    local pick = nums((by.RewardAmount_TXT or ""):gsub("/", " of "))
    if by.RewardHeadText and not pick:match("^%s*0 of 0%s*$") then out[#out + 1] = by.RewardHeadText .. ", " .. pick end
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
                    -- Not the widget's design-time "#999" (events.lua).
                    if amount:find("%d") and not amount:find("#", 1, true) then rewards[#rewards + 1] = amount .. " " .. res end
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
    return M.text_from(parts_under(path), path)
end

-- The text of a window from its parts (parts_under), in reading order.
function M.text_from(parts, path)
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

-- Which watched windows are open comes from the game's own events, not
-- from a scan: the 300 ms scan over every watched class (and every text in
-- the game for windows read again), the 3 s walk over every widget for
-- subclasses and the 500 ms save scan held the game long enough to swallow
-- keys (E on the Mess Hall, 14 of 56 lost with the mod's loops, 36 of 36
-- without; firefly82, 2026-10-21). The window census of 2026-10-21
-- (probes/2026-10-21/windowcensus.lua, 30 minutes of play) showed what each
-- window calls:
--   room window, event, pause menu: BP_OnActivated, BP_OnDeactivated
--   event steps: OnOpened, OnChoiceResult, SetOutcomeText, DisplayResults,
--     DisplayRewards
--   build ring: OnOpenRadial, BPInitWithMenuData, OnCloseRadial
--   detail view: OnShow, ShowDetailView, OnUpdateDisplayEvent, OnHideEvent,
--     HideDetailView
--   reports (construction, research, energy loss, emergency rations):
--     ApplyInfo
--   loading screen: SetLoadingScreenText; save notice: StartDisplay
-- The scan read those reports 4 to 7 s after the game showed them (the
-- construction report at 08:18:49 was read at 08:18:56).
--
-- Classes are found as the game makes their widgets (NotifyOnNewObject on
-- UserWidget, one table lookup per widget); a watched class, or one built
-- on a watched class, gets its events hooked the first time, on the class
-- in its chain that defines each (ForEachFunction, no search). A widget
-- made with no event of its own is looked at once on the next tick.

-- Events that say the window is the game's current one: read even if a
-- parent is still fading in (texts inside the window must be shown).
local OPEN_EVENTS = { BP_OnActivated = true, OnOpened = true, OnOpenRadial = true, OnShow = true,
    ShowDetailView = true, ApplyInfo = true, StartDisplay = true, SetLoadingScreenText = true,
    SetDilemmaText = true, OnOverviewInfoActivated = true }
-- Events that change what an open window shows: read again if on screen.
local CHANGE_EVENTS = { OnChoiceResult = true, SetOutcomeText = true, DisplayResults = true,
    DisplayRewards = true, BPInitWithMenuData = true, OnUpdateDisplayEvent = true,
    OnTabChangedEvent = true, UpdateText = true, SetData = true, Construct = true }
-- Closing an info card (Sensor Alert, a crew log) calls none of
-- CloseInfoWidget, OnCloseClicked or CallOnCloseEvent (all hooked in a
-- test, VM, 2026-10-21); M.check_gone sees it go instead.
local CLOSE_EVENTS = { BP_OnDeactivated = true, OnCloseRadial = true, OnHideEvent = true,
    HideDetailView = true, Hide = true, Destruct = true, CloseInfoWidget = true }
-- Native classes whose Blueprint events never reach a hook on the native
-- function itself (the census hooked them there and saw nothing).
local BASE = { ["/Script/UMG.UserWidget"] = true, ["/Script/UMG.Widget"] = true,
    ["/Script/CommonUI.CommonActivatableWidget"] = true, ["/Script/CommonUI.CommonUserWidget"] = true,
    ["/Script/UMG.Visual"] = true, ["/Script/CoreUObject.Object"] = true }

local open = {}         -- path -> class name, from an open event until a close event
local result_token = 0  -- the newest event-result wait (its 10 s limit)
local order_of = {}     -- class name -> its place in WATCH (reading order)
local function rebuild_order()
    for i, c in ipairs(WATCH) do order_of[c] = order_of[c] or i end
end
rebuild_order()

-- The watched windows on screen now, outermost first, nested ones dropped,
-- in WATCH order (a tutorial's title before its page).
-- A window the game destroyed instead of hiding was dropped here without a
-- word to the close listeners: a Construction Report's CLOSE never counted
-- as closed, so the ship view did not put the pointer back on the room
-- and the next E did nothing (VM, 2026-10-22). Set below, where the
-- listeners are.
local dropped = nil

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
    for p, cls in pairs(open) do
        local w = StaticFindObject(p)
        -- A loading screen the game has closed but not destroyed (after New
        -- Game in the demo's first run) stays "shown" by every widget flag:
        -- no parent, outer the game instance, not in the viewport even while
        -- loading. CommonUI's IsActivated tells: true during a load, false
        -- after (probes in the full game and the demo, 2026-10-21). Kept, it
        -- held every view announcement for the whole game.
        -- Skipped, not forgotten: it comes back the moment the game
        -- activates it again (Fable review).
        local stale = false
        if cls == "WBP_Loading_Screen_C" and w and w:IsValid() then
            local oka, act = pcall(function() return w:IsActivated() end)
            stale = oka and act == false
        end
        if not (w and w:IsValid()) then
            open[p] = nil
            if dropped then
                local dp, dc = p, cls
                ExecuteInGameThread(function() pcall(dropped, dp, dc) end)
            end
        elseif not stale and not ((in_game and cls == "WBP_Sandbox_Setup_C") or (skip_room and cls == "WBP_RoomManagementV2_C"))
            and screen.shown(w) then
            found[#found + 1] = p
            order[p] = order_of[cls] or 1e9
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
    table.sort(outer, function(a, b) return order[a] < order[b] end)
    return outer
end

-- The watched windows on screen now (focus.lua focuses one that opens
-- with nothing focused).
M.open_windows = on_screen

-- The shown window of one of the watched classes in set (class name ->
-- true), and its path, or nil: from the windows' own open and close
-- events, and the new ones not shown when they were made (fresh), so no
-- class is searched. focus.lua asked FindAllOf for a dozen classes on every
-- look, after every key (2026-10-25). test (optional) replaces "shown".
local fresh   -- below, with the other records of new widgets
function M.open_of(set, test)
    for p, cls in pairs(open) do
        if set[cls] then
            local w = StaticFindObject(p)
            if w and w:IsValid() and (test or screen.shown)(w) then return w, p end
        end
    end
    for p in pairs(fresh) do
        local w = StaticFindObject(p)
        if w and w:IsValid() and set[w:GetClass():GetFName():ToString()] and (test or screen.shown)(w) then return w, p end
    end
    return nil
end

-- Dry run for development: what would be spoken now, without speaking.
function M.preview()
    local lines = {}
    for _, p in ipairs(on_screen()) do
        lines[#lines + 1] = p:match("([%w_]+)$") .. ": " .. M.text_under(p)
    end
    return table.concat(lines, " || ")
end

-- A loading screen is up: its progress line ("Caching Shaders 67.61%"),
-- "" when it shows none, nil with no loading screen. A new campaign's first
-- load ran about two minutes in silence, and arrows and Enter seemed to do
-- nothing (player report, full game, 2026-10-24); keys.lua says this then.
-- From the open windows, so a closed loading screen the game keeps does not
-- count.
function M.loading_step()
    for _, p in ipairs(on_screen()) do
        if open[p] == "WBP_Loading_Screen_C" then
            for _, part in ipairs(parts_under(p)) do
                if part.path:find("%.StepText$") then
                    -- Whole percent: "67.61%" said in full each time.
                    return (part.text:gsub("(%d+)[%.,]%d+%%", "%1%%"))
                end
            end
            return ""
        end
    end
    return nil
end

-- A tutorial opens with keyboard focus on an unlabeled helper button, and
-- Tab and the arrows do not leave it (Casey was stuck twice, 2026-10-10).
-- SetFocus on its Close button did not move focus, so Enter closes an open
-- tutorial directly instead (focus.lua calls this first). Clicking Close
-- this way is proven (it opened the next tutorial, 2026-10-10).
-- A tutorial is on screen (keys.lua answers the arrows with how to close it).
function M.tutorial_open()
    for p, cls in pairs(open) do
        if cls == "WBP_TutorialInfoWidget_C" then
            local w = StaticFindObject(p)
            if w and w:IsValid() and screen.shown(w) then return true end
        end
    end
    return false
end

function M.close_tutorial()
    for p, cls in pairs(open) do
        if cls == "WBP_TutorialInfoWidget_C" then
            local w = StaticFindObject(p)
            if w and w:IsValid() and screen.shown(w) then
                local close = w.CloseButton
                if close and close:IsValid() then
                    print("[VoyagerAccess] tutorial: close\n")
                    M.tutorial_closed_at = os.clock()
                    close:HandleButtonPressed()
                    close:HandleButtonReleased()
                    close:HandleButtonClicked()
                    return true
                end
            end
        end
    end
    return false
end

-- Windows already read are kept in a file, so reloading the mod during
-- development does not read the open windows to Casey again.
local SEEN_PATH = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\windows-read.txt"

-- Only for a reload in the same run of the game: object paths repeat from
-- one run to the next, and a list kept from an earlier run made the personal
-- log after a load count as read, so it was never spoken (VM, 2026-10-21).
-- The helper deletes the file when it starts the game; the first line also
-- keeps os.clock() (time since the game started), and a list written later
-- in its run than now is from another run.
local function save_announced()
    local f = io.open(SEEN_PATH, "w")
    if not f then return end
    f:write("clock ", string.format("%.3f", os.clock()), "\n")
    for p in pairs(announced) do f:write(p, "\n") end
    f:close()
end

local function load_announced()
    local f = io.open(SEEN_PATH, "r")
    if not f then return end
    local first = f:read("l")
    local saved = first and tonumber(first:match("^clock (%S+)$"))
    if saved and saved <= os.clock() then
        for line in f:lines() do announced[line] = true end
    end
    f:close()
end

local settle = {}      -- kept for the close path below

-- Reads one window. reread: the game says what it shows has changed.
local function read_window(p, reread)
    crumb.at("popups: read " .. p)
    local text = M.text_under(p)
    -- The start warning a slot's Enter raises is closed by focus.lua
    -- at once; reading it first was only noise (2026-10-14).
    local quiet = p:find("FewerHeroesConfirmWidget", 1, true)
        and os.clock() < (require("focus").quiet_start_warning_until or 0)
    -- Battle toasts name a ship's side as the screen draws it
    -- ("Voyager Shield Down: Right"); L says bow, aft, port and
    -- starboard, so the toasts do too (VM, 2026-10-14).
    if p:find("Toast_Notification", 1, true) then
        local SIDES = { Right = "starboard", Left = "port", Front = "bow", Back = "aft", Rear = "aft" }
        text = text:gsub(":%s*(%a+)(%.?)$", function(w, dot)
            return SIDES[w] and (": " .. require("tr").word(SIDES[w]) .. dot) or nil
        end)
        -- "Subsystem Destroyed: Weapons" did not say whose.
        local sys = text:match("Subsystem Destroyed:%s*([%a ]-)%.?$")
        local low = false
        if not sys then
            sys = text:match("Subsystem HP low:%s*([%a ]-)%.?$")
            low = sys ~= nil
        end
        local okw, owner = pcall(function() return sys and require("combat").destroyed_owner(sys, low) end)
        if okw and owner then text = text:gsub(":%s*" .. sys, function() return ": " .. require("tr").fill("{s}'s {s}", owner, sys) end, 1) end
    end
    -- The warning's buttons ("Continue", "Return"), read with its message
    -- since 2026-10-16, are left out by tree_parts now, by class: the
    -- English words matched here missed every other language.
    -- The away mission summary counts up as it fills in, and was read
    -- three times over (2026-10-14). It is read when the mission window
    -- says it has shown the consequences (dialogue.lua asks for it), and
    -- after that only its changed sentences. OPEN POINT: the census did not
    -- reach the end of an away mission, so which of the window's
    -- consequence events comes last is not seen yet.
    local outcome = p:find("WBP_AwayMissionOutcome", 1, true) ~= nil
    local waiting = false
    local spoken = nil
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
            or p:find("WBP_FirstPerformanceSelection_C", 1, true) or p:find("WBP_GammaCorrection_C", 1, true)
            -- Held by focus.lua until read, so its button is said here
            -- (sector 7 end, VM, 2026-10-18).
            or p:find("WBP_MissionInfoWidget_C", 1, true) or p:find("WBP_SideMissionFinished_C", 1, true))
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
        -- description alone (OnChoiceResult), and that was read again with
        -- CONTINUE before the result (Icy Planetoid, VM, 2026-10-15). A
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
            -- "CONTINUE" came first (Abandoned Vessel, VM, 2026-10-15): the
            -- result is read with the button after it. Held until the game
            -- shows the result (its DisplayResults), not for a set time.
            -- Only while no options are left: a stage that keeps options
            -- must let the focused one be said (review, 2026-10-15).
            local options_left = false
            for _, ob in ipairs(FindAllOf("WBP_POISelectableOption_C") or {}) do
                if ob:IsValid() and path_of(ob):find("^/Engine/Transient%.") and screen.shown(ob) then
                    options_left = true
                end
            end
            M.result_pending = not options_left
            -- At most 10 s: if DisplayResults never comes, focus was held
            -- for good and CONTINUE never said (the 0.3.67 limit, Icy
            -- Planetoid, 2026-10-15; review of firefly82's patch,
            -- 2026-10-21).
            if M.result_pending then
                result_token = result_token + 1
                local mine = result_token
                ExecuteInGameThreadWithDelay(10000, function()
                    if result_token == mine and M.result_pending then
                        M.result_pending = false
                        print("[VoyagerAccess] popup: no event result in 10 s, focus speech released\n")
                        pcall(function() require("focus").reannounce() end)
                    end
                end)
            end
        else
        M.result_pending = false
        -- Tutorials are not cut off by the next window (speech.lua).
        -- The page is its own window (WBP_TUT_CenterView and the
        -- like), and only the two-word title was protected, so the
        -- next dialogue line cut the page off (firefly82, German
        -- game, 2026-10-18).
        if p:find("Tutorial", 1, true) or p:find("WBP_TUT_", 1, true) then
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
                -- The battle result after Auto Resolve: focus is still on
                -- Auto Resolve's Proceed as the result is read, and "Proceed,
                -- 2 of 2" came between the result and its own "Proceed, 5
                -- of 5" (Q Trial, VM, 2026-10-22). The focus move says it.
                local cur = require("focus").current_path()
                if p:find("CombatResultView", 1, true) and cur and cur:find(".AutoResolveWidget.", 1, true) then return end
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
        spoken = text
    end
    if not waiting then last_text[p] = text end
    return spoken
end

-- The save notice ("autosave", WBP_SavegameNotification; a manual save
-- said nothing at all, VM, 2026-10-17): said on its StartDisplay, queued,
-- so it never cuts off what is being read.
local function say_save(p)
    local text = nil
    for _, part in ipairs(M.parts_under and M.parts_under(p) or {}) do
        if not text and part.text ~= "" then text = part.text end
    end
    local say = text and (text:sub(1, 1):upper() .. text:sub(2)) or "Saving"
    print("[VoyagerAccess] save: " .. say .. "\n")
    speech.say(say, false)
end

-- A tutorial's page is its own widget with no event (WBP_TUT_*View,
-- WBP_TutorialScreen*): read with its frame, then the tutorial closes by
-- itself (Casey asked, 2026-10-10; R repeats it).
local PAGE_CLASSES = {}
for _, c in ipairs(WATCH) do
    if c:find("^WBP_TUT_") or c:find("^WBP_TutorialScreen") then PAGE_CLASSES[#PAGE_CLASSES + 1] = c end
end

-- Other parts of the mod told when a window has been read or has closed
-- (help.lua says where you are once a room or event closes), so they need
-- no scan of their own.
local read_listeners, close_listeners = {}, {}
function M.on_read(fn) read_listeners[#read_listeners + 1] = fn end
function M.on_close(fn) close_listeners[#close_listeners + 1] = fn end
local function tell(list, ...)
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then print("[VoyagerAccess] popups listener error: " .. tostring(err) .. "\n") end
    end
end
dropped = function(p, cls)
    print("[VoyagerAccess] popups: closed " .. (p:match("([%w_]+)$") or "?") .. " (destroyed)\n")
    tell(close_listeners, p, cls)
end

-- Other parts told when the game makes a widget of a class they name
-- (view.lua: the navigation bar, help.lua: the main menu): fn(path) on the
-- next tick. The same pass over new widgets as the windows', no scan.
local widget_subs = {}
function M.on_widget(class_name, fn)
    widget_subs[class_name] = widget_subs[class_name] or {}
    table.insert(widget_subs[class_name], fn)
end

local function after_change()
    save_announced()
    pcall(function() require("focus").request_settle() end)
end

local queued = {}   -- path -> { kind = "open" | "change" | "close", trust }
-- New widgets of a watched class, or of a class not seen yet, from the
-- moment the game makes them until their first look is queued: focus.lua
-- said a side mission offer's option before the offer's text, because the
-- offer's class was seen for the first time and its look was not queued
-- yet when focus looked (WBP_MultipleChoiceWidget_C, 12:23:27, firefly82,
-- 2026-10-21). path -> class name.
local made = {}
fresh = {}    -- path -> true: a new watched widget not shown yet (declared above M.open_of)
local reopen_wait = {}   -- path -> true while a shown-again window waits to be read
local reopen_gen = {}    -- path -> count of closes, so a waiting read knows its showing ended

-- One window event, handled on the next tick (a pre hook: the game fills
-- the window inside the function).
local CHANGE_RETRY_MS = { 60, 120, 250, 500, 1000 }   -- after a read that said nothing new (below)
local room_wait = {}   -- path -> "tab" or "modules": a room window waiting for that game event
local room_hooked = false   -- OnLoadedModuleClasses is hooked (M.install)
local room_tab_hooked = false   -- the room window's tab switcher event is hooked (M.install)
function M.room_tab_event() return room_tab_hooked end
local room_tab_seen = {}   -- path -> true: the game has set this showing's tab
local card_active = {}   -- path -> true: an info card seen activated this showing (closed_card)
-- retry: how many of those looks this is (nil for the event itself).
local function process(p, kind, trust, retry)
    local w = StaticFindObject(p)
    if kind == "close" then
        if open[p] or announced[p] then
            print("[VoyagerAccess] popups: closed " .. (p:match("([%w_]+)$") or "?") .. "\n")
        end
        local was = open[p]
        open[p], announced[p], last_text[p], settle[p] = nil, nil, nil, nil
        -- A read waiting after a reopen is for a showing that is over.
        reopen_wait[p] = nil
        room_wait[p] = nil
        room_tab_seen[p] = nil
        card_active[p] = nil
        reopen_gen[p] = (reopen_gen[p] or 0) + 1
        M.result_pending = false
        after_change()
        tell(close_listeners, p, was)
        return
    end
    if not (w and w:IsValid() and p:find("^/Engine/Transient%.")) then return end
    local cls = w:GetClass():GetFName():ToString()
    -- A window the game shows again (it keeps the widget: a room window, a
    -- toast, the same energy-loss report two cycles running) kept its
    -- "read" mark and last text, and the same text again was silent (review
    -- of firefly82's patch, 2026-10-21; 0.3.67 reset both when a window left
    -- the screen). It also gets its open event before it fills in the new
    -- content: a room window opened a second time was read as "Room." (demo,
    -- VM, 2026-10-21). So its marks are cleared now, focus waits for it, and
    -- it is read a moment later.
    if kind == "open" and trust and (announced[p] or last_text[p]) then
        announced[p], last_text[p] = nil, nil
        open[p] = open[p] or cls
        if not reopen_wait[p] then
            reopen_wait[p] = true
            local gen = reopen_gen[p] or 0
            -- 400 ms: at 200 the room description was still missing once,
            -- after a conversation (demo, VM, 2026-10-21).
            ExecuteInGameThreadWithDelay(400, function()
                -- Closed in the meantime: nothing to read (GPT review,
                -- 2026-10-21: the trusted read brought a closed window back).
                if (reopen_gen[p] or 0) ~= gen or not reopen_wait[p] then return end
                reopen_wait[p] = nil
                local ok, err = pcall(process, p, "change", true)
                if not ok then print("[VoyagerAccess] popups reopen error: " .. tostring(err) .. "\n") end
            end)
        end
        return
    end
    local shown = screen.shown(w)
    if not trust and not shown then
        -- A new widget of a watched kind, not on screen yet: the first one
        -- of its class can be shown before its class's events are hooked
        -- (the census missed the first side mission offer that way), so it
        -- is looked at again on the next input or window event
        -- (M.recheck_fresh), until it is shown or gone.
        if kind == "change" and not announced[p] then fresh[p] = true end
        return
    end
    fresh[p] = nil
    open[p] = open[p] or cls
    -- Seen activated while open: closed_card may count it closed later.
    pcall(function() if w:IsActivated() == true then card_active[p] = true end end)
    if cls == "WBP_SavegameNotification_C" then
        if kind == "open" then say_save(p) end
        return
    end
    -- Inside another open window: read with it, not alone.
    for _, o in ipairs(on_screen()) do
        if o ~= p and p:sub(1, #o + 1) == o .. "." then
            if not (p:find("WBP_AM_ConfirmStart_C", 1, true) or p:find("FewerHeroesConfirmWidget", 1, true)) then
                return process(o, "change", true)
            end
        end
    end
    local reread = announced[p] == true
    -- A room window builds its modules (power, description, crew, the
    -- room's own tab) only after it is activated: BP_OnActivated came with
    -- none, and the game's own OnLoadedModuleClasses about 46 ms later, with
    -- all of them filled on the next tick, on every opening (probe,
    -- Krankenstation, 2026-10-22). So a room window without modules is not
    -- read yet; the game's event reads it (M.install). No timer: 0.3.70
    -- looked every 80 ms for up to 400 ms (room_wait). Focus waits for the
    -- window's read as before.
    -- Read once the game has set the window's tab, not when its modules
    -- are built: the window builds on its power tab, unseen, and then
    -- switches to the tab it shows (the Mess Hall's rations, the Sickbay's
    -- patients) with its switcher's OnActiveIndexChanged, as it becomes
    -- visible; a room that stays on the power tab gets the same event with
    -- index 0, its modules in place (probe 2026-10-22, roomorder.lua). Read
    -- at the modules, the Mess Hall was read with the power tab's
    -- description, which the screen never shows, and before it was shown,
    -- so no "Ship view" came after Escape. Without the tab event (its class
    -- not hooked yet), the modules event as above.
    if cls == "WBP_RoomManagementV2_C" and not reread then
        -- A backstop only, if the event never comes (a reused window set
        -- again to the tab it is already on was not probed): read after
        -- 600 ms, as 0.3.70's 400 ms wait did (Fable review, 2026-10-22).
        local function wait_for(kind)
            room_wait[p] = kind
            ExecuteInGameThreadWithDelay(600, function()
                if room_wait[p] ~= kind then return end
                room_wait[p] = nil
                room_tab_seen[p] = true   -- so this read does not wait again
                print("[VoyagerAccess] popups: room window " .. kind .. " event did not come, reading\n")
                local ok, err = pcall(process, p, "change", true)
                if not ok then print("[VoyagerAccess] popups room read error: " .. tostring(err) .. "\n") end
            end)
        end
        if room_tab_hooked then
            if not room_tab_seen[p] then
                wait_for("tab")
                return
            end
        elseif room_hooked and not room_tab_seen[p] then
            local okm, built = pcall(function() return require("rooms").modules_built(w) end)
            if okm and not built then
                wait_for("modules")
                return
            end
        end
    end
    -- Activated but a parent still fading in: the census saw a room window's
    -- BP_OnActivated with the window not yet shown. Its texts count as shown
    -- if they are shown inside the window (screen.shown with the window as
    -- the stop).
    read_stop = (not shown) and w or nil
    read_last_try = (retry or 0) >= #CHANGE_RETRY_MS
    local okr, spoken = pcall(read_window, p, reread)
    read_stop, read_last_try = nil, true
    if not okr then print("[VoyagerAccess] popups read error: " .. tostring(spoken) .. "\n"); spoken = nil end
    -- Read only once something was said or it is really on screen: a window
    -- with nothing to say yet stays unread, so its next event reads it.
    if spoken or shown then announced[p] = true end
    local said = { spoken }
    -- A tutorial's frame: its page too, then close it.
    if cls == "WBP_TutorialInfoWidget_C" then
        for _, pc in ipairs(PAGE_CLASSES) do
            for _, pw in ipairs(FindAllOf(pc) or {}) do
                local pp = pw:IsValid() and path_of(pw)
                if pp and pp:find("^/Engine/Transient%.") and not announced[pp] and screen.shown(pw) then
                    open[pp] = pc
                    said[#said + 1] = read_window(pp, false)
                    announced[pp] = true
                end
            end
        end
        -- It stays open until Enter, as for a sighted player, who can read
        -- it again while it is up; it used to close as soon as it was read
        -- (firefly82's review; Casey chose this, 2026-10-23). R repeats it.
    end
    local texts = {}
    for _, s in ipairs(said) do if s then texts[#texts + 1] = s end end
    if #texts > 0 then require("dialogue").remember(table.concat(texts, ". ")) end
    after_change()
    if spoken then tell(read_listeners, p, cls) end
    -- A change event can come before the game has put the new content in
    -- (the Overview's OnTabChangedEvent: the old tab was still there, and
    -- the new one was read 400 to 650 ms after the key; NVDA log times, VM,
    -- 2026-10-21). With nothing new read, the window is looked at again a
    -- few times shortly after; reading a window takes a few ms now. Only
    -- the Overview: an event's result fills in over several events, and a
    -- look between them could say half of it.
    -- A window's opening read that said nothing too: the personal log after
    -- a load was read before its text was in, has no later event, and was
    -- never read (VM, 2026-10-21).
    -- Any window's first read counts, whatever event led to it: the log's
    -- first read came from the new-widget look (a "change"), not an open.
    local again = (kind == "change" and cls == "WBP_OverviewInfoWidget_C") or kind == "open" or not reread
        or (retry or 0) > 0
    if again and not spoken and (retry or 0) < #CHANGE_RETRY_MS then
        local n = (retry or 0) + 1
        local gen = reopen_gen[p] or 0
        ExecuteInGameThreadWithDelay(CHANGE_RETRY_MS[n], function()
            -- Not while a reopen read is waiting: both read the window, the
            -- first half filled (Fable review).
            if (reopen_gen[p] or 0) ~= gen or queued[p] or reopen_wait[p] then return end
            local ok, err = pcall(process, p, "change", trust, n)
            if not ok then print("[VoyagerAccess] popups retry error: " .. tostring(err) .. "\n") end
        end)
    end
end

local function queue(p, kind, trust)
    if not p then return end
    local q = queued[p]
    if q then
        -- Within one tick an open or close outranks a change.
        if kind ~= "change" then q.kind = kind end
        q.trust = q.trust or trust
        return
    end
    queued[p] = { kind = kind, trust = trust }
    ExecuteInGameThread(function()
        local e = queued[p]
        queued[p] = nil
        local ok, err = pcall(process, p, e.kind, e.trust)
        if not ok then print("[VoyagerAccess] popups error: " .. tostring(err) .. "\n") end
    end)
end

-- Info cards close with no event the mod can hook: the game does it all in
-- C++. Probed on 2026-10-22 with "Overwrite save" and "Return to main
-- menu?" (both built on GXCommonInfoWidget, like the Sensor Alert): no
-- CloseInfoWidget, OnCloseClicked, CallOnCloseEvent, DeactivateWidget,
-- RemoveFromParent, SetVisibility, container RemoveWidget or Blueprint
-- event of the card came. But the card's own state is final in the same
-- call as the click: IsActivated() false (closestate.lua). So it is read
-- right after the mod's own click and after any input, with no wait; a
-- card a button only hides for a moment stays activated, so it is not
-- taken for closed. Every class built on GXCommonInfoWidget counts: 0.3.70
-- checked only WBP_CommonInfoWidget_C itself, and never saw the two cards
-- above close. The reports are built on it too (Construction, Research and
-- Energy Loss reports: a Construction Report's CLOSE left no "closed" in
-- the log, so the ship's pointer stayed on that button for the next E; VM,
-- 2026-10-22).
-- Only a card seen activated counts as closed when it no longer is: an
-- embedded card its parent shows with SetVisibility (the away mission's
-- "unassigned slots" confirm, on GXCommonInfoWidget_EmbeddedReusable) may
-- never be activated at all (Fable review, 2026-10-22).
local INFO_BASE = nil
local function closed_card(p)
    local w = StaticFindObject(p)
    if not (w and w:IsValid()) then return true end
    INFO_BASE = INFO_BASE or StaticFindObject("/Script/GameXcite.GXCommonInfoWidget")
    if not (INFO_BASE and INFO_BASE:IsValid() and w:IsA(INFO_BASE)) then return false end
    local ok, active = pcall(function() return w:IsActivated() end)
    if not ok then return false end
    if active == true then card_active[p] = true; return false end
    if active == false and card_active[p] then
        card_active[p] = nil
        return true
    end
    return false
end
-- focus.lua asks after pressing a window's button and after every input:
-- every open window is checked, not only the list's first window (Fable
-- review: a button list joins the buttons of every open window).
function M.check_gone()
    for p in pairs(open) do
        if closed_card(p) then queue(p, "close", false) end
    end
end

-- The windows of one watched class read again, when another part of the
-- game says their content is final (dialogue.lua: the away mission window
-- has shown its consequences, for WBP_AwayMissionOutcome_C).
function M.reread_class(cls)
    for _, w in ipairs(FindAllOf(cls) or {}) do
        local p = w:IsValid() and path_of(w)
        if p and p:find("^/Engine/Transient%.") then queue(p, "change", false) end
    end
end

-- The new watched widgets not shown yet, looked at once more (focus.lua
-- calls this on each look it takes; nothing runs on a timer).
function M.recheck_fresh()
    for p in pairs(fresh) do
        local w = StaticFindObject(p)
        if not (w and w:IsValid()) then
            fresh[p] = nil
        elseif screen.shown(w) then
            fresh[p] = nil
            queue(p, "change", false)
        end
    end
end

-- An open window not read yet holds focus speech only while it is shown,
-- or for 2 s while it may still be fading in: one opened by a trusted event
-- but never shown, whose read said nothing, held focus speech for good
-- (review of firefly82's patch, 2026-10-21).
local unread_since = {}   -- path -> os.clock() of the first look that found it unread
local function holds(p)
    if announced[p] then unread_since[p] = nil return false end
    local w = StaticFindObject(p)
    if not (w and w:IsValid()) then return false end
    if screen.shown(w) then return true end
    if not unread_since[p] then
        unread_since[p] = os.clock()
        -- When the grace runs out, the button it held is said.
        ExecuteInGameThreadWithDelay(2100, function()
            if unread_since[p] and not announced[p] then
                pcall(function() require("focus").reannounce() end)
            end
        end)
    end
    return os.clock() - unread_since[p] < 2
end

-- True while the window at path is on screen and not read yet (focus.lua
-- holds a button inside it; Auto Resolve's "Proceed" came before the
-- window, as its class is a named part of the battle setup and its open
-- event came after focus moved; VM, 2026-10-21).
function M.window_unread(p)
    if not p or announced[p] then return false end
    local w = StaticFindObject(p)
    return w ~= nil and w:IsValid() and screen.shown(w)
end

-- Reads a shown window that no event brings here: the away team setup's
-- unassigned-slots warning is a named part of the setup, never in
-- open_windows, so it was never read and focus.lua's list for it waited
-- for that read and said nothing (Enter on "start mission" was silent,
-- Profile 03 Dark Frontier, VM, 2026-10-23).
function M.read_now(p)
    if not M.window_unread(p) then return end
    local ok, err = pcall(process, p, "change", true)
    if not ok then print("[VoyagerAccess] popups read_now error: " .. tostring(err) .. "\n") end
end

-- True while a window of one of the classes in set (name -> true) is open
-- or waiting to be read, and not read yet.
function M.unread_of(set)
    for _, cls in pairs(made) do
        if set[cls] then return true end
    end
    for p, cls in pairs(open) do
        if set[cls] and holds(p) then return true end
    end
    for p in pairs(queued) do
        local cls = p:match("([%w_]+_C)_%d+$")
        if cls and set[cls] and not announced[p] then return true end
    end
    return false
end

-- True while a window event waits to be read: focus.lua holds the focused
-- button until the window's own text has been said (it used to look for any
-- unread window by scanning 11 classes).
function M.read_pending()
    if next(queued) ~= nil then return true end
    for p in pairs(open) do
        if holds(p) then return true end
    end
    return M.result_pending == true
end

-- Hooks ---------------------------------------------------------------------

local watched_set = {}
for _, c in ipairs(WATCH) do watched_set[c] = true end
local class_seen = {}    -- class name -> true (hooked) or false (not watched)
local hooked_fn = {}     -- function path -> true

local function on_event(name, kind, trust)
    return function(ctx)
        local okp, p = pcall(function() return path_of(ctx:get()) end)
        if okp and p then queue(p, kind, trust) end
    end
end

-- The watched class cls stands for (itself, or the watched class it is
-- built on: WBP_Dialogue_Window_Intro and the like), or nil.
local function watched_base(cls)
    local k, d = cls, 0
    while k and k:IsValid() and d < 8 do
        local n = k:GetFName():ToString()
        if watched_set[n] then return n end
        k, d = k:GetSuperStruct(), d + 1
    end
    return nil
end

local function hook_class(cls)
    local name = cls:GetFName():ToString()
    if class_seen[name] ~= nil then return class_seen[name] end
    local base = watched_base(cls)
    class_seen[name] = base ~= nil
    if not base then return false end
    if base ~= name then
        WATCH[#WATCH + 1] = name
        watched_set[name] = true
        rebuild_order()
        order_of[name] = order_of[base]
        if LAYOUTS[base] and not LAYOUTS[name] then LAYOUTS[name] = LAYOUTS[base] end
        print("[VoyagerAccess] popups: watching " .. name .. " as a kind of " .. base .. "\n")
    end
    local got, taken = {}, {}
    local k = cls
    while k and k:IsValid() do
        local kpath = path_of(k)
        if not kpath or BASE[kpath] then break end
        k:ForEachFunction(function(f)
            local fname = f:GetFName():ToString()
            local kind = (OPEN_EVENTS[fname] and "open") or (CHANGE_EVENTS[fname] and "change")
                or (CLOSE_EVENTS[fname] and "close") or nil
            -- The nearest definition only: an override is what runs.
            if kind and not taken[fname] then
                taken[fname] = true
                local fpath = kpath .. ":" .. fname
                if not hooked_fn[fpath] then
                    local ok = pcall(RegisterHook, fpath, on_event(fname, kind, OPEN_EVENTS[fname] == true))
                    hooked_fn[fpath] = ok
                end
                got[#got + 1] = fname
            end
        end)
        k = k:GetSuperStruct()
    end
    if name == "WBP_BattleResultLCARS_C" then pcall(M.ensure_damage_hook) end
    print("[VoyagerAccess] popups: " .. name .. " events: " .. (#got > 0 and table.concat(got, ", ") or "none") .. "\n")
    return true
end

M.parts_under = parts_under

function M.install()
    load_announced()
    -- Every widget the game makes passes here: one name lookup, and for a
    -- class not seen before one check on the next tick.
    local okn, err = pcall(NotifyOnNewObject, "/Script/UMG.UserWidget", function(o)
        local okc, cls = pcall(function() return o:GetClass() end)
        if not (okc and cls) then return end
        local name = cls:GetFName():ToString()
        local subs = widget_subs[name]
        if subs then
            local okq, q = pcall(function() return path_of(o) end)
            if okq and q then
                ExecuteInGameThread(function() tell(subs, q) end)
            end
        end
        if class_seen[name] == false then return end
        -- A class not seen before is hooked now, as its first widget is
        -- made: hooked on the next tick, the first room window of a session
        -- had already been activated, its BP_OnActivated was missed, and
        -- only a timed focus look found its focus 430 ms later (probe e1,
        -- 2026-10-24). Its events run after this, when the game adds and
        -- activates the widget.
        if class_seen[name] == nil then pcall(hook_class, cls) end
        local okp, p = pcall(function() return path_of(o) end)
        if okp and p then made[p] = name end
        ExecuteInGameThread(function()
            pcall(function()
                local is_watched = class_seen[name]
                if is_watched == nil then is_watched = hook_class(cls) end
                -- A new widget of a watched kind: looked at once (made
                -- with no event of its own, or before its class was hooked).
                if is_watched and okp and p then queue(p, "change", false) end
            end)
            if okp and p then made[p] = nil end
        end)
    end)
    print("[VoyagerAccess] popups: new widgets " .. (okn and "watched" or ("not watched: " .. tostring(err))) .. "\n")
    -- A room window's modules are in place on the tick after this (see
    -- process). A native function of the room window's C++ class, called
    -- through the game's reflection on every opening (probe 2026-10-22),
    -- so it can be hooked when the mod starts. Without it, room windows are
    -- read at once, as before 0.3.70.
    local ROOM_EVENT = "/Script/STVoyager.STVRoomManagementV2:OnLoadedModuleClasses"
    if StaticFindObject(ROOM_EVENT) then
        room_hooked = pcall(RegisterHook, ROOM_EVENT, function(ctx)
            local okp, p = pcall(function() return path_of(ctx:get()) end)
            if not (okp and p) then return end
            ExecuteInGameThread(function()
                if room_wait[p] ~= "modules" then return end
                room_wait[p] = nil
                queue(p, "change", true)
            end)
        end)
    end
    print("[VoyagerAccess] popups: room window modules event " .. (room_hooked and "hooked" or "not hooked") .. "\n")
    -- The room window Blueprint's tab switcher event (see process), hooked
    -- on its class when the game first makes a room window.
    local TAB_EVENT = "BndEvt__WBP_RoomManagementV2_WidgetSwitcher_K2Node_ComponentBoundEvent_1_OnActiveIndexChangedDelegate__DelegateSignature"
    local function hook_room_tab(path)
        if room_tab_hooked then return end
        local w = path and StaticFindObject(path)
        if not (w and w:IsValid()) then return end
        local cp = path_of(w:GetClass())
        if not (cp and StaticFindObject(cp .. ":" .. TAB_EVENT)) then return end
        room_tab_hooked = pcall(RegisterHook, cp .. ":" .. TAB_EVENT, function(ctx)
            local okp, p = pcall(function() return path_of(ctx:get()) end)
            if not (okp and p) then return end
            ExecuteInGameThread(function()
                room_tab_seen[p] = true
                -- The game focuses the new page once its fade is over
                -- (focus.look_after_switch): on opening and on Left/Right.
                -- A tab the player switched to is read then too, after the
                -- look (rooms.tab_shown).
                pcall(function()
                    require("focus").after_switch(function() return StaticFindObject(p).WidgetSwitcher end, function()
                        require("focus").request_check()
                        ExecuteInGameThread(function() pcall(require("rooms").tab_shown, p) end)
                    end, "room tab")
                end)
                if room_wait[p] ~= "tab" then return end
                room_wait[p] = nil
                queue(p, "change", true)
            end)
        end)
        print("[VoyagerAccess] popups: room window tab event " .. (room_tab_hooked and "hooked" or "not hooked") .. "\n")
    end
    M.on_widget("WBP_RoomManagementV2_C", hook_room_tab)
    for _, w in ipairs(FindAllOf("WBP_RoomManagementV2_C") or {}) do
        local p = w:IsValid() and path_of(w)
        if p and p:find("^/Engine/Transient%.") then hook_room_tab(p) end
    end
    -- Windows that exist already (the main menu, a reload): once.
    for _, c in ipairs(WATCH) do
        for _, w in ipairs(FindAllOf(c) or {}) do
            local p = w:IsValid() and path_of(w)
            if p and p:find("^/Engine/Transient%.") then
                pcall(hook_class, w:GetClass())
                if screen.shown(w) then
                    open[p] = c
                    queue(p, "change", false)
                end
            end
        end
    end
end

return M
