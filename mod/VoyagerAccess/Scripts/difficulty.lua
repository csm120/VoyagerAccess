-- The full game's difficulty window (WBP_GameDifficulty_C), opened by New
-- Campaign: four mode cards (Custom, Adventure, Survival, Years of Hell) and
-- Back. Custom opens Custom Difficulty Settings inside the same window
-- (CustomSettingsWidget): three presets, fifteen settings in eight sections,
-- Start Game (a hold button) and Back. Found 2026-10-14 in the VM.
--
-- Each window is one list, Up and Down in reading order (Casey: new screens
-- are lists), "n of m" on each item. The cards' descriptions and bullet
-- points are rich text the plain label missed ("Survival" was all that was
-- said). On a setting, Left and Right change the value: the game's own
-- Left and Right only moved between the two columns, and the arrow buttons
-- (LeftButton, RightButton) ignored a click from the mod; the row's mouse
-- arrow events (leftButton_MKB, rightButton_MKB) change it (heard: Research
-- times 100% to 75%).
local speech = require("speech")
local screen = require("screen")

local M = {}

local NAV_LEFT, NAV_RIGHT, NAV_UP, NAV_DOWN = 0, 1, 2, 3   -- EUINavigation
local STOP = 3                                             -- EUINavigationRule

-- Back (CloseButton) is an action bar button that never takes focus; Escape
-- is the way back, so it is not in the lists.
local MODES = { "CustomizeButton", "StoryModeButton", "NormalModeButton", "HardcoreModeButton" }
local PRESETS = { AdventureSet_Button = true, SurvivalSet_Button = true, YearsOfHellSet_Button = true }
-- Reading order on screen (left column, then right), with the heading each
-- one sits under. Headings are read from the window, not written here.
local SETTINGS = {
    { "ChallengeMode", "TextBlock_83" },
    { "FinalWarning", "TextBlock_1" },
    { "HomesicknessPenalty", "TextBlock_1" },
    { "TooMuchTimeInSector", "TextBlock_1" },
    { "TooMuchTimeInSectorDelay", "TextBlock_1" },
    { "ResourceDepositSize", "TextBlock" },
    { "BaseStorageCapacity", "TextBlock" },
    { "EnemyCombatPower", "TextBlock_6" },
    { "DialogueCheckChances", "TextBlock_3" },
    { "ConstructionTime", "TextBlock_2" },
    { "ResearchTime", "TextBlock_2" },
    { "TreatmentTime", "TextBlock_2" },
    { "AwayMissionDifficulty", "TextBlock_5" },
    { "AwayMissionExperience", "TextBlock_5" },
    { "PointOfInterestPositiveOutcomes", "TextBlock_4" },
}
local CUSTOM = { "AdventureSet_Button", "SurvivalSet_Button", "YearsOfHellSet_Button" }
for _, s in ipairs(SETTINGS) do CUSTOM[#CUSTOM + 1] = s[1] .. "_Setting" end
CUSTOM[#CUSTOM + 1] = "StartGameButton"
local SECTION_OF = {}
for _, s in ipairs(SETTINGS) do SECTION_OF[s[1] .. "_Setting"] = s[2] end

local function path_of(obj)
    return obj:GetFullName():match("^%S+%s+(.+)$")
end

local function valid(o) return o ~= nil and o:IsValid() end

-- Plain words from a text widget: rich text tags and spare spaces removed.
local function text(w)
    if not valid(w) then return "" end
    local ok, s = pcall(function() return w:GetText():ToString() end)
    if not ok or type(s) ~= "string" or s:sub(1, 1) == "#" then return "" end
    s = s:gsub("<[^>]*/>", ""):gsub("<[^>]*>", "")
    return (s:gsub("[ \t]+", " "):match("^%s*(.-)%s*$"))
end

local function one_line(s) return (s:gsub("%s+", " ")) end

-- "ENABLED" read as a word, not shouted: capitals become "Enabled".
local function word_case(s)
    if s:find("%a") and s == s:upper() then
        return s:sub(1, 1) .. s:sub(2):lower()
    end
    return s
end

-- "- Resources are limited\n\n- Dialogues and away missions are\nmore
-- challenging" -> { "Resources are limited", "Dialogues and away missions
-- are more challenging" }: a line without a dash continues the one before.
local function bullets(s)
    local out = {}
    for line in s:gmatch("[^\r\n]+") do
        local item = line:match("^%s*%-%s*(.-)%s*$")
        if item then
            out[#out + 1] = item
        elseif #out > 0 and line:find("%S") then
            out[#out] = out[#out] .. " " .. line:match("^%s*(.-)%s*$")
        end
    end
    return out
end

local function sentence(s)
    s = s:gsub("%s+$", "")
    if s == "" or s:find("[%.!?]$") then return s end
    return s .. "."
end

-- The difficulty window a path is in, and whether Custom is showing.
local function window_of(path)
    local wpath = path and path:match("^(.-WBP_GameDifficulty_C_%d+)")
    local w = wpath and StaticFindObject(wpath)
    if not valid(w) then return nil end
    local csw = w.CustomSettingsWidget
    return w, valid(csw) and screen.shown(csw) and csw or nil
end

function M.handles(path)
    return path ~= nil and path:find("WBP_GameDifficulty_C_%d+%.") ~= nil
end

-- The window's items in list order, as paths; only those on screen.
local function items(w, csw)
    local owner, names = w, MODES
    if csw then owner, names = csw, CUSTOM end
    local out = {}
    for _, n in ipairs(names) do
        local b = owner[n]
        if valid(b) and screen.shown(b) then out[#out + 1] = path_of(b) end
    end
    return out
end

local state = nil         -- which window and page was last spoken
local list = {}           -- its items, as paths
local last_section = nil  -- the heading last spoken in Custom
local pending = nil       -- { path, title }: the page title, said with that item

-- Up and Down along the list, stopping at its ends. On settings, Left and
-- Right stop too: they change the value (M.adjust), and the game's own
-- moved focus to the other column at the same time.
local function wire()
    for i, p in ipairs(list) do
        local b = StaticFindObject(p)
        if valid(b) then pcall(function()
            local up, down = list[i - 1] and StaticFindObject(list[i - 1]), list[i + 1] and StaticFindObject(list[i + 1])
            if valid(up) then b:SetNavigationRuleExplicit(NAV_UP, up) else b:SetNavigationRuleBase(NAV_UP, STOP) end
            if valid(down) then b:SetNavigationRuleExplicit(NAV_DOWN, down) else b:SetNavigationRuleBase(NAV_DOWN, STOP) end
            if SECTION_OF[p:match("([%w_]+)$")] then
                b:SetNavigationRuleBase(NAV_LEFT, STOP)
                b:SetNavigationRuleBase(NAV_RIGHT, STOP)
            end
        end) end
    end
    print(string.format("[VoyagerAccess] difficulty: %d items wired\n", #list))
end

local function position(path)
    for i, p in ipairs(list) do
        if p == path then return string.format("%d of %d", i, #list) end
    end
    return nil
end

local function mode_label(b)
    local parts = { text(b.HeadlineText) }
    local desc = text(b.DescriptionTextBlock)
    if desc ~= "" then parts[#parts + 1] = sentence(one_line(desc)) end
    if valid(b.BulletPointsTextBlock) and screen.shown(b.BulletPointsTextBlock) then
        for _, item in ipairs(bullets(text(b.BulletPointsTextBlock))) do parts[#parts + 1] = sentence(item) end
    end
    return parts
end

-- The section headings are not properties of the window (designer texts
-- without a variable), so they are found by name inside its widget tree.
local headings = {}   -- widget name -> text, for the open Custom page
-- Read in the page's own widget tree (screen.walk), not by searching every
-- text in the game (review of 0.3.70, 2026-10-22); a heading not shown is
-- not on screen, so it is not read.
local TEXT_CLASS, RICH_CLASS = nil, nil
local function texts_in(owner, cls, fn)
    screen.walk(owner, function(w)
        if not w:IsA(cls) then return false end
        fn(w, path_of(w))
        return true
    end, { no_lists = true })
end
local function read_headings(csw)
    headings = {}
    TEXT_CLASS = TEXT_CLASS or StaticFindObject("/Script/UMG.TextBlock")
    if not (valid(csw) and TEXT_CLASS and TEXT_CLASS:IsValid()) then return end
    local prefix = path_of(csw) .. ".WidgetTree"
    texts_in(csw, TEXT_CLASS, function(t, p)
        -- Directly in the page's own tree, not inside a setting row.
        local n = p and p:sub(1, #prefix) == prefix and p:sub(#prefix + 1):match("^_%d+%.(TextBlock[_%d]*)$")
        if n then headings[n] = text(t) end
    end)
end

-- A page's title ("Select a difficulty mode", "Custom Difficulty
-- Settings"): ReportContent, also a designer text with no property.
local function title_of(owner)
    RICH_CLASS = RICH_CLASS or StaticFindObject("/Script/UMG.RichTextBlock")
    if not (valid(owner) and RICH_CLASS and RICH_CLASS:IsValid()) then return "" end
    local prefix = path_of(owner) .. ".WidgetTree"
    local found = ""
    texts_in(owner, RICH_CLASS, function(t, p)
        if found == "" and p and p:sub(1, #prefix) == prefix and p:sub(#prefix + 1):match("^_%d+%.ReportContent$") then
            found = text(t)
        end
    end)
    return found
end

local function setting_label(csw, b, name)
    local heading = SECTION_OF[name] and headings[SECTION_OF[name]] or ""
    local head = { text(b.TextBlock), word_case(text(b.Value)) }
    local parts = { head }
    if heading ~= "" and heading ~= last_section then
        table.insert(parts, 1, word_case(heading))
        last_section = heading
    end
    local desc = text(b.DescriptionText)
    return parts, desc
end

-- The spoken label for a focused item, or nil to say nothing (focus is
-- being moved to the top of a newly opened page).
function M.label(b, path)
    local w, csw = window_of(path)
    if not w then return nil end
    local key = path:match("^(.-WBP_GameDifficulty_C_%d+)") .. (csw and ":custom" or ":modes")
    if key ~= state then
        state = key
        last_section = nil
        list = items(w, csw)
        wire()
        if csw then read_headings(csw) end
        -- The title goes with the first item spoken on the page. Kept by
        -- path: labels are asked for more than once per move, and the first
        -- asker used it up (the title was never heard, 2026-10-14).
        local title = title_of(csw or w)
        pending = { path = path, title = title }
        -- Custom opened on Dialogue checks, the top of the second column;
        -- start at the top of the list instead.
        if csw and list[1] and list[1] ~= path then
            pending.path = list[1]
            local first = StaticFindObject(list[1])
            if valid(first) then first:SetFocus() return nil end
        end
    end
    -- Kept until another item is spoken after it: the old item can be asked
    -- for again before the focus move to the top takes.
    local title = nil
    -- Said once: the same item asked for again within a second is the same
    -- move; later (End at the top, L) it is not.
    if pending and pending.said_at and os.clock() - pending.said_at > 1 then pending = nil end
    if pending and pending.path == path then
        title = pending.title
        pending.said_at = pending.said_at or os.clock()
    elseif pending and pending.said_at then
        pending = nil
    end
    local name = path:match("([%w_]+)$")
    local pos = position(path)
    local out = {}
    if title and title ~= "" then out[#out + 1] = sentence(word_case(title)) end
    if SECTION_OF[name] and csw then
        local parts, desc = setting_label(csw, b, name)
        local head = parts[#parts]
        if #parts > 1 then out[#out + 1] = sentence(parts[1]) end
        local line = head[1] .. ", " .. head[2]
        if pos then line = line .. ", " .. pos end
        out[#out + 1] = sentence(line)
        if desc ~= "" then out[#out + 1] = sentence(one_line(desc)) end
    elseif not csw and name ~= "CloseButton" and valid(b.HeadlineText) then
        local parts = mode_label(b)
        out[#out + 1] = sentence(parts[1] .. (pos and (", " .. pos) or ""))
        for i = 2, #parts do out[#out + 1] = parts[i] end
    else
        -- Presets, Start Game (its "[HOLD]" tag left out) and Back.
        local words = {}
        for _, n in ipairs({ "ButtonText", "ButtonName", "StartGameText", "Text" }) do
            local t = text(b[n])
            if t ~= "" then words[#words + 1] = word_case(t) end
        end
        local label = words[1] or (name == "StartGameButton" and "Start Game") or name
        if PRESETS[name] then
            label = label .. " preset"
            local ok, sel = pcall(function() return b:GetSelected() end)
            if ok and sel then label = label .. ", selected" end
        end
        if name == "StartGameButton" then label = "Start Game" end
        out[#out + 1] = sentence(label .. (pos and (", " .. pos) or ""))
    end
    return table.concat(out, " ")
end

-- Home and End: the first or last item of the list. The rows sit in one
-- box per section, so the general Home and End stopped inside a section.
function M.edge(path, last)
    if not M.handles(path) or #list == 0 then return false end
    local b = StaticFindObject(last and list[#list] or list[1])
    if valid(b) then b:SetFocus() end
    return true
end

-- Left and Right on a Custom setting change its value and say the new one.
-- True when it was a setting.
function M.adjust(path, left)
    if not (M.handles(path) and SECTION_OF[path:match("([%w_]+)$") or ""]) then return false end
    local b = StaticFindObject(path)
    if not valid(b) then return true end
    local before = text(b.Value)
    local ok, err = pcall(function()
        if left then
            b:BndEvt__WBP_GameDifficulty_CustomSettings_Setting_leftButton_MKB_K2Node_ComponentBoundEvent_1_OnButtonClickedEvent__DelegateSignature()
        else
            b:BndEvt__WBP_GameDifficulty_CustomSettings_Setting_rightButton_MKB_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature()
        end
    end)
    if not ok then print("[VoyagerAccess] difficulty adjust error: " .. tostring(err) .. "\n") return true end
    -- The value text is the new one in the same call as the event (probe
    -- 2026-10-22: Research time 100% to 125% at once), so it is read now,
    -- not 150 ms later. "before" is read ahead of the event: read after it,
    -- the log said the new value twice.
    local now = word_case(text(b.Value))
    print("[VoyagerAccess] difficulty: " .. path:match("([%w_]+)$") .. " " .. before .. " to " .. now .. "\n")
    speech.say(now, true)
    return true
end

return M
