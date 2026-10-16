-- Reads the dialogue window (speaker and line) and lets Enter continue it.
-- The game maps dialogue Continue/Skip only to the left mouse button and the
-- gamepad (IMC_Dialogue_Map, the game's own key bindings), so the mod injects
-- the game's own input action. Proven 2026-10-10: injecting
-- IA_Dialogue_Continue advanced Janeway's lines.

local speech = require("speech")
local screen = require("screen")

local M = {}

local INTERVAL_MS = 150
-- The window's PATH, not the window: a UObject kept across ticks went stale
-- when the dialogue ended and crashed UE4SS (2026-10-10 21:55, symbolized).
local window_path = nil
local last_line = nil       -- last line spoken
local typing = nil          -- line seen on the previous poll
local speaker_wait = {}     -- { line, polls } while waiting for a speaker name
local last_speaker = nil    -- the name said with the last line
local last_spoken = nil     -- "Speaker: line", kept after the window closes, for R
local continue_action = nil
-- Declared here because poll() uses them; declared below it, poll() saw
-- empty globals and the second half of a one-Enter continue never ran.
local continue_pending = false
local inject_continue

local function live(obj)
    local name = obj:GetFullName()
    return name:find(" /Engine/Transient.", 1, true) ~= nil
end

-- The full-screen dialogue, and the smaller side panel over the ship view
-- (Janeway to Engineering, 2026-10-10; its parent class is the Sector one).
-- FindAllOf did not return the side panel for the first class, so each
-- class is listed. All have DialogueText, DialogueSpeakerText and the popup.
-- The away mission window too (2026-10-11: its text was never read).
-- WBP_Dialogue_Window_Intro_C is a subclass of the Sector one (the Intro_Text
-- dialogue tables); FindAllOf skips subclasses, so it is listed too (2026-10-15).
local WINDOW_CLASSES = { "WBP_Dialogue_Window_C", "WBP_Dialogue_Window_SideView_C", "WBP_Dialogue_Window_Sector_C",
    "WBP_Dialogue_Window_Intro_C", "WBP_Dialogue_Window_AwayMission_C" }

local function find_window()
    if window_path then
        local w = StaticFindObject(window_path)
        -- A hidden window must not hide the other kind behind it.
        if w and w:IsValid() and screen.shown(w) then return w end
        window_path = nil
    end
    for _, class in ipairs(WINDOW_CLASSES) do
        for _, w in ipairs(FindAllOf(class) or {}) do
            if w:IsValid() and live(w) and screen.shown(w) then
                window_path = w:GetFullName():match("^%S+%s+(.+)$")
                return w
            end
        end
    end
    return nil
end

-- "Gentlemen, welcome to <italic>Voyager</>. " -> "Gentlemen, welcome to Voyager."
local function plain(s)
    s = require("text").prep(s)  -- icons beside numbers, list line breaks (text.lua)
    s = s:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", "\""):gsub("&#39;", "'")
    return (s:gsub("<[^>]*>", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- The open dialogue window, or nil. Use it within the current tick only.
function M.active()
    local w = find_window()
    if w and screen.shown(w) then return w end
    return nil
end

-- True when the widget path is inside the dialogue window (a choice button).
function M.contains(path)
    local w = find_window()
    if not (w and path) then return false end
    local wpath = w:GetFullName():match("^%S+%s+(.+)$")
    return wpath ~= nil and path:sub(1, #wpath + 1) == wpath .. "."
end

-- The line types out a few letters at a time; speaking every change made
-- Casey hear "Gentle", "Gentlemen, we", ... The typewriter widget keeps the
-- whole line in TargetText, so speak that at once. If it is ever empty, fall
-- back to the shown text once it is the same on two polls in a row (that
-- made Casey wait about 3 s per line).
-- The game shows "Character Name" before the real speaker loads; Casey heard
-- "Character Name: Gentlemen, welcome to Voyager." Wait for the real name.
local PLACEHOLDER_SPEAKER = "Character Name"

local function speak_story(text)
    last_spoken = text
    print("[VoyagerAccess] dialogue: " .. text .. "\n")
    speech.say_story(text)
end

-- Story cards ("Into the Badlands") are a popup inside the dialogue window,
-- with a title and a paragraph and their own Continue button.
local last_popup = nil
local function poll_popup(w)
    local ok, popup = pcall(function() return w.WBP_Dialogue_Popup end)
    if not (ok and popup and popup:IsValid() and screen.shown(popup)) then
        last_popup = nil
        return
    end
    local title = plain(popup.PopUpTitleText:GetText():ToString())
    local body = plain(popup.PopupText:GetText():ToString())
    -- "Incoming!" already ends a sentence; ". " after it read "Incoming!."
    local sep = title:match("[%.!?]$") and " " or ". "
    local card = (title ~= "" and title .. sep or "") .. body
    if body == "" or card == last_popup then return end
    last_popup = card
    speak_story(card)
    -- Its button is said after it (focus.lua does not say it): "CONTINUE"
    -- came before "Hull breach on deck four!" (VM, 2026-10-15).
    speech.say("Continue", false)
end

local crumb = require("crumb")

local function poll()
    if continue_pending then
        crumb.at("dialogue: inject continue")
        continue_pending = false
        inject_continue()
    end
    crumb.at("dialogue: find window")
    local w = M.active()
    -- last_line is kept while the window is hidden: resetting it re-spoke
    -- the same line whenever the window came back (twice on 2026-10-10).
    if not w then
        typing = nil
        return
    end
    crumb.at("dialogue: popup")
    poll_popup(w)
    crumb.at("dialogue: line")
    local text = w.DialogueText
    if not (text and text:IsValid()) then return end
    local ok, target = pcall(function() return text.TargetText:ToString() end)
    local line, settled
    if ok and target and target ~= "" then
        line, settled = plain(target), true
    else
        line = plain(text:GetText():ToString())
        settled = line == typing
    end
    typing = line
    if line == "" or line == last_line or not settled then return end
    local sp = w.DialogueSpeakerText
    -- The away mission window keeps the placeholder in a hidden speaker
    -- field, so its lines were never read (2026-10-11): a hidden speaker
    -- counts as none.
    local speaker = (sp and sp:IsValid() and screen.shown(sp)) and plain(sp:GetText():ToString()) or ""
    if speaker == PLACEHOLDER_SPEAKER then return end
    -- The first line after a cutscene settled before its speaker was shown,
    -- so "Kathryn Janeway" was left off (2026-10-14, twice). Give the name
    -- up to about a second; a window that never shows one (away missions)
    -- is read after that.
    if speaker_wait.line ~= line then speaker_wait = { line = line, polls = 0 } end
    speaker_wait.polls = speaker_wait.polls + 1
    if speaker == "" and sp and sp:IsValid() and speaker_wait.polls <= 7 then return end
    -- The first line of the next dialogue table shows the old name for a
    -- moment: "Kathryn Janeway: Captain, the source appears to be a...
    -- Federation beacon" is Tuvok's (DT_DR_Main_02_Maneuvers_Part_01a,
    -- after her choice; Casey's machine, 2026-10-15). The same name as the
    -- last line waits up to two polls (0.3 s) for a new one.
    if speaker ~= "" and speaker == last_speaker and speaker_wait.polls <= 2 then return end
    last_speaker = speaker
    last_line = line
    speak_story(speaker ~= "" and (speaker .. ": " .. line) or line)
end

-- R repeats the last dialogue line or story card. Not Space: the game uses Space for away
-- missions and combat, and UE4SS key binds do not stop the key reaching it.
-- R is unbound in every input context (the game's own key bindings).
-- A dialogue choice (WBP_Dialogue_Choice_Sector). Focus sits on its
-- LeftButton, whose only text is the choice's number, so Casey heard "1",
-- "2" (2026-10-11). The wording is RightButton's Choice text, and a
-- requirement is in WBP_Dialogue_Requirement: "[<ColorPositive>Sensor
-- Array</> - Chance: 100%]" (ColorNegative when not met).
local function text_of(w)
    if not (w and w:IsValid()) then return "" end
    local ok, s = pcall(function() return w:GetText():ToString() end)
    return ok and s or ""
end

-- WBP_Dialogue_Choice_C is the bridge dialogue's choice (the Caretaker
-- hail, 2026-10-14): focus sat on its number button (LeftButton) and only
-- "1" was read. It is built like the sector choice.
local function sector_choice_path(path)
    return path and (path:match("^(.-WBP_Dialogue_Choice_Sector_C_%d+)") or path:match("^(.-WBP_Dialogue_Choice_C_%d+)"))
end

-- Up and Down did not move between these choices (2026-10-14): each
-- choice's number button and text button get explicit rules to the same
-- buttons of the choices above and below, in the panel's order.
local wired_sig = nil
local unavailable_said = nil   -- the choice set whose unavailable choices were read

local function shown_choices()
    local list = {}
    for _, cls in ipairs({ "WBP_Dialogue_Choice_C", "WBP_Dialogue_Choice_Sector_C" }) do
        for _, c in ipairs(FindAllOf(cls) or {}) do
            if c:IsValid() and c:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(c) then
                local idx = 0
                pcall(function() idx = c:GetParent():GetChildIndex(c) end)
                list[#list + 1] = { c = c, idx = idx }
            end
        end
    end
    table.sort(list, function(a, b) return a.idx < b.idx end)
    return list
end

-- Home and End: the first or last choice (Home did nothing, so Enter took
-- the choice still focused, 2026-10-14).
function M.choice_edge(path, last)
    if not sector_choice_path(path) then return false end
    local list = shown_choices()
    local it = list[last and #list or 1]
    if not it then return false end
    local side = path:match("%.(RightButton)$") or "LeftButton"
    pcall(function() it.c[side]:SetFocus() end)
    return true
end

-- Up and Down on a choice when the game does not move: the Caretaker's
-- choices on the bridge had the explicit rules and still did not move
-- (VM, 2026-10-14). Shortly after the key, if the same choice still has
-- focus, the mod moves it; where the game does move, nothing happens here.
function M.choice_step(path, dir)
    if not sector_choice_path(path) then return false end
    local list = shown_choices()
    local side = path:match("%.(RightButton)$") or "LeftButton"
    local i = nil
    for k, it in ipairs(list) do
        if path:sub(1, #it.c:GetFullName():match("^%S+%s+(.+)$")) == it.c:GetFullName():match("^%S+%s+(.+)$") then i = k end
    end
    if not i then return false end
    local from = list[i].c:GetFullName():match("^%S+%s+(.+)$")
    local to = list[i + dir] and list[i + dir].c:GetFullName():match("^%S+%s+(.+)$")
    if not to then return true end
    ExecuteInGameThreadWithDelay(200, function()
        pcall(function()
            local fc = StaticFindObject(from)
            local tc = StaticFindObject(to)
            -- Judged by the mod's own focus: on the bridge no button had
            -- keyboard focus at all, and a keyboard focus test moved one
            -- choice too many when the game had moved too. If the mod still
            -- has the same choice, nothing moved.
            if fc and fc:IsValid() and tc and tc:IsValid() and require("focus").current_path() == path then
                print("[VoyagerAccess] dialogue: moving to the next choice myself\n")
                tc[side]:SetFocus()
            end
        end)
    end)
    return true
end

local function wire_choices()
    local list = shown_choices()
    local names = {}
    for i, it in ipairs(list) do names[i] = it.c:GetFName():ToString() end
    local sig = table.concat(names, "|")
    if sig == wired_sig then return end
    wired_sig = sig
    for i, it in ipairs(list) do
        for _, side in ipairs({ "LeftButton", "RightButton" }) do
            pcall(function()
                local b = it.c[side]
                local up = list[i - 1] and list[i - 1].c[side]
                local down = list[i + 1] and list[i + 1].c[side]
                if up then b:SetNavigationRuleExplicit(2, up) else b:SetNavigationRuleBase(2, 3) end
                if down then b:SetNavigationRuleExplicit(3, down) else b:SetNavigationRuleBase(3, 3) end
            end)
        end
    end
end

function M.is_choice(path)
    if path and sector_choice_path(path) then pcall(wire_choices) end
    return path ~= nil and (sector_choice_path(path) ~= nil
        or path:find("WBP_Dialogue_Choice_AwayMission_C_%d+%.WidgetTree_%d+%.RightButton") ~= nil)
end

-- An away mission choice (WBP_Dialogue_Choice_AwayMission, read
-- 2026-10-11): RightButton.ChoiceText has the wording, AttributeAmount the
-- skill value needed, AttributeImage the skill's icon ("MI_UI_Science").
-- Heroes and Lock In are inside.

local function away_choice_label(c)
    local parts = {}
    local wording = ""
    pcall(function() wording = plain(text_of(c.RightButton.ChoiceText)) end)
    if wording ~= "" then parts[#parts + 1] = wording end
    local amount = plain(text_of(c.AttributeAmount))
    if amount ~= "" and amount ~= "-" then
        local skill = "skill"
        pcall(function()
            local ro = c.AttributeImage.Brush.ResourceObject
            if ro and ro:IsValid() then skill = ro:GetFName():ToString():match("^MI_UI_(%a+)") or skill end
        end)
        parts[#parts + 1] = "Needs " .. skill .. " " .. amount
    end
    -- A trait shown with the choice ("[Pilot]", "[Quick-witted]") was not
    -- read (full game, VM, 2026-10-14).
    pcall(function()
        local rt = c.RightButton.RequirementText
        if rt and rt:IsValid() and screen.shown(rt) then
            local t = plain(text_of(rt)):gsub("^%[", ""):gsub("%]$", "")
            if t ~= "" then parts[#parts + 1] = "Trait: " .. t end
        end
    end)
    -- Risk is not read yet: riskLvl_1 to riskLvl_3 are always visible (the
    -- level is drawn some other way, likely by color), and reading them said
    -- "High risk" for every choice (2026-10-11).
    if #parts == 0 then return nil end
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    -- No period after ! or ? ("Demand to know what is going on!.", 2026-10-11).
    return ((table.concat(parts, ". ") .. "."):gsub("([!?])%.", "%1"))
end

M.away_choice_label = away_choice_label

function M.choice_label(path)
    local apath = path:match("^(.-WBP_Dialogue_Choice_AwayMission_C_%d+)")
    if apath then
        local c = StaticFindObject(apath)
        return (c and c:IsValid()) and away_choice_label(c) or nil
    end
    local cpath = sector_choice_path(path)
    local c = cpath and StaticFindObject(cpath)
    if not (c and c:IsValid()) then return nil end
    local parts = {}
    -- Its number, as shown on its left ("1" to "4").
    local number = ""
    pcall(function()
        for _, t in ipairs(FindAllOf("TextBlock") or {}) do
            local tp = t:IsValid() and t:GetFullName():match("^%S+%s+(.+)$")
            if tp and tp:sub(1, #cpath + 1) == cpath .. "." and tp:find("LeftButton", 1, true) and screen.shown(t) then
                local s = plain(text_of(t))
                if s:match("^%d+$") then number = s end
            end
        end
    end)
    local wording = ""
    pcall(function() wording = text_of(c.RightButton.Choice) end)
    -- Costs drawn as an icon and a number ("Expander <img id="Duranium"/>
    -- <ColorPositive>15</> <img id="Tritanium"/> <ColorPositive>10</>")
    -- were read "Expander 15 10" (Kazon in need, VM, 2026-10-15).
    local costs = {}
    wording = wording:gsub('%s*<img id="(%w+)"%s*/>%s*<(%w+)>%s*([%d,]+)%s*</>', function(res, color, n)
        costs[#costs + 1] = n .. " " .. (res:gsub("(%l)(%u)", "%1 %2")) .. (color == "ColorNegative" and ", not enough" or "")
        return ""
    end)
    if #costs > 0 then wording = wording .. ". Costs " .. table.concat(costs, ", ") end
    wording = plain(wording):gsub("^%[[Oo][Pp][Tt][Ii][Oo][Nn][Aa][Ll]%]%s*", "Optional: ")
    -- A note in brackets at the end ran into the wording with punctuation
    -- off: "Send Tuvok to investigate Warning: Becomes unavailable" (text
    -- scan, 2026-10-15). Its own sentence instead.
    wording = wording:gsub("([^%s%.])%s*%[([^%]{}]+)%]%s*$", "%1. %2")
    if wording ~= "" then parts[#parts + 1] = wording end
    -- The requirement widget is not a named member, so find its text by path.
    local req = ""
    local want = cpath .. "."
    for _, cls in ipairs({ "TextBlock", "RichTextBlock", "CommonTextBlock", "CommonRichTextBlock" }) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            local tp = t:IsValid() and t:GetFullName():match("^%S+%s+(.+)$")
            if tp and tp:sub(1, #want) == want and tp:find("WBP_Dialogue_Requirement", 1, true)
                and screen.shown(t) then
                req = text_of(t)
            end
        end
    end
    if req ~= "" and not req:find("^##") then
        local unmet = req:find("ColorNegative", 1, true) ~= nil
        -- "Phaser Control Room Level 1- Chance: 50% + 35%" has no space
        -- before the dash (Mirror, Mirror, VM, 2026-10-15).
        req = plain(req):gsub("^%[", ""):gsub("%]$", ""):gsub("%s*%-%s*Chance:", ", chance")
        -- The second number is the hero's bonus, shown highlighted: "chance
        -- 40% + 45%" read as a sum to work out (Jetrel, 2026-10-15).
        req = (req:gsub("chance (%d+%%) %+ (%d+%%)", "chance %1, plus %2 bonus"))
        parts[#parts + 1] = (unmet and "Needs " or "") .. req
    end
    local reward = ""
    pcall(function() reward = plain(text_of(c.RightButton.Reward)) end)
    if reward ~= "" then parts[#parts + 1] = reward end
    -- A major decision is picked by holding (bRequiresHold), outlined in
    -- gold on screen; Enter holds it for you (focus.lua).
    local okh, hold = pcall(function() return c.RightButton.bRequiresHold end)
    if okh and hold == true and #parts > 0 then parts[#parts + 1] = "Major decision" end
    if #parts == 0 then return nil end
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    local text = table.concat(parts, ". ") .. "."
    if number ~= "" then
        -- How many there are: "Choice 1" alone did not say whether others
        -- followed (2026-10-14).
        local count = 0
        pcall(function()
            local cls = c:GetClass():GetFName():ToString()
            for _, o in ipairs(FindAllOf(cls) or {}) do
                if o:IsValid() and o:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(o) then count = count + 1 end
            end
        end)
        text = "Choice " .. number .. (count > 0 and (" of " .. count) or "") .. ": " .. text
    end
    -- Choices that cannot be taken get no focus, so the arrows skipped them
    -- unheard: of five at the Nezu colony only 4 and 5 were reachable (Rise,
    -- VM, 2026-10-16). A disabled one says so; the first time a set is read,
    -- the ones out of reach are added, as events add their locked options.
    local okd, disabled = pcall(function() return not c.LeftButton:GetIsEnabled() end)
    if okd and disabled then
        text = text:gsub("%.$", "") .. ". Not available."
    else
        local others, names = {}, {}
        for _, it in ipairs(shown_choices()) do
            names[#names + 1] = it.c:GetFName():ToString()
            local ok2, off = pcall(function() return not it.c.LeftButton:GetIsEnabled() end)
            if ok2 and off and it.c:GetFullName() ~= c:GetFullName() then
                local okl, l = pcall(M.choice_label, it.c:GetFullName():match("^%S+%s+(.+)$") .. ".LeftButton")
                if okl and l then
                    others[#others + 1] = (l:gsub("%s*Not available%.$", ""):gsub("%.$", ""):gsub("^Choice (%d+) of %d+:", "Choice %1:"))
                end
            end
        end
        local sig = table.concat(names, "|")
        if #others > 0 and unavailable_said ~= sig then
            unavailable_said = sig
            text = text .. " Not available: " .. table.concat(others, "; ") .. "."
        end
    end
    return text
end

-- Other readers (tutorials, toasts) add their text for R to repeat.
function M.remember(text)
    last_spoken = text
end

-- Who said the last line, for I.
function M.speaker()
    return last_speaker
end

function M.repeat_line()
    -- An open window (an event, a room, a detail view) is read again in
    -- full, as when it opened: R gave only an event's locked option and the
    -- event's own text could not be heard again (2026-10-14). Its locked
    -- options are part of that text.
    do
        local oko, summary = pcall(function()
            for _, w in ipairs(FindAllOf("WBP_AwayMissionOutcome_C") or {}) do
                if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(w) then
                    return require("awaymission").outcome_text(w:GetFullName():match("^%S+%s+(.+)$"))
                end
            end
        end)
        if oko and summary and summary ~= "" then
            speech.say(summary, true)
            return
        end
        local okw, text = pcall(function()
            local popups, out = require("popups"), {}
            for _, p in ipairs(popups.open_windows()) do
                -- In dialogue, only the away mission summary (the mission
                -- window is a dialogue): R gave the last line, not the
                -- summary (2026-10-14).
                if M.active() and not p:find("WBP_AwayMissionOutcome_C", 1, true) then goto next end
                do
                    -- The Construction Report came out twice (two widgets
                    -- read the same way, 2026-10-14).
                    local t = popups.text_under(p)
                    local dup = false
                    for _, o in ipairs(out) do if o == t then dup = true end end
                    if t and t ~= "" and not dup then out[#out + 1] = t end
                end
                ::next::
            end
            return table.concat(out, ". ")
        end)
        if okw and text and text ~= "" then
            speech.say(text, true)
            return
        end
    end
    -- While an event with locked options is open, R reads those options:
    -- they take no focus, so this is how Casey reaches them (2026-10-11).
    local ok, locked = pcall(function() return require("events").locked_summary() end)
    if ok and locked ~= "" then
        speech.say(locked, true)
        return
    end
    speech.say(last_spoken or "Nothing to repeat", true)
end

local function find_action(context_name, action_name)
    for _, ctx in ipairs(FindAllOf("InputMappingContext") or {}) do
        if ctx:GetFName():ToString() == context_name then
            local found = nil
            ctx.Mappings:ForEach(function(_, e)
                local m = e:get()
                if m.Action:IsValid() and m.Action:GetFName():ToString() == action_name then found = m.Action end
            end)
            if found then return found end
        end
    end
    return nil
end

local function input_subsystem()
    for _, s in ipairs(FindAllOf("EnhancedInputLocalPlayerSubsystem") or {}) do
        if s:IsValid() and live(s) then return s end
    end
    return nil
end

function inject_continue()
    continue_action = (continue_action and continue_action:IsValid()) and continue_action
        or find_action("IMC_Dialogue_Map", "IA_Dialogue_Continue")
    local sub = input_subsystem()
    if not (continue_action and sub) then
        print("[VoyagerAccess] dialogue: continue action not found\n")
        return
    end
    print("[VoyagerAccess] dialogue: continue\n")
    sub:InjectInputVectorForAction(continue_action, { X = 1.0, Y = 0.0, Z = 0.0 }, {}, {})
end

-- Continue while a line is still typing only finishes the typing, so Casey
-- needed two Enters per line (log, 2026-10-10). The mod speaks the whole line
-- at once, so finish the typing first and continue on the next poll.

function M.continue()
    local w = M.active()
    local text = w and w.DialogueText
    if text and text:IsValid() and not text:HasFinishedPlayingLine() then
        text:SkipToLineEnd(false)
        continue_pending = true
        return
    end
    inject_continue()
end

-- Shift+Enter: "hold to skip". The game's skip actions need a 1.0 s hold of
-- the mouse or gamepad, so the mod calls what fires at the end of the hold.
-- Dialogue: SkipToNextChoiceTriggered does the whole skip in one call
-- (finishes the line and jumps to the next choices). Called once:
-- repeating it could skip past choices. Not yet proven.
--
-- Cutscenes: injecting IA_CutsceneSkip every frame did NOT skip (Casey,
-- 2026-10-10), so call the cutscene pawn's own handlers directly, as the end
-- of a held skip does: Triggered alone did nothing, Started then Triggered
-- skipped the intro (proven).
-- Only look for the pawn while a cutscene is really playing (its input
-- context is applied). Touching the leftover pawn during a dialogue crashed
-- UE4SS inside its AActor wrapper (Shift+Enter, 2026-10-10 22:17).
function M.cutscene_playing()
    local sub = input_subsystem()
    if not sub then return false end
    for _, ctx in ipairs(FindAllOf("InputMappingContext") or {}) do
        if ctx:GetFName():ToString() == "IMC_Cutscene" and sub:HasMappingContext(ctx, {}) then
            return true
        end
    end
    return false
end

local function cutscene_pawn()
    if not M.cutscene_playing() then return nil end
    for _, p in ipairs(FindAllOf("STVCutscenePawn") or {}) do
        if p:IsValid() and p:GetFullName():find("PersistentLevel", 1, true) then return p end
    end
    return nil
end

-- Dialogue first: the cutscene pawn may outlive its cutscene.
function M.skip()
    crumb.at("key: shift+enter")
    local w = M.active()
    if w then
        print("[VoyagerAccess] dialogue: skip\n")
        speech.say("Skipping", true)
        w:SkipToNextChoiceTriggered()
        return
    end
    local pawn = cutscene_pawn()
    if not pawn then
        speech.say("Nothing to skip", true)
        return
    end
    print("[VoyagerAccess] cutscene: skip\n")
    speech.say("Skipping", true)
    pawn:OnSkipActionStarted({})
    pawn:OnSkipActionTriggered({})
end

function M.install()
    local keys = require("keys")
    keys.on("r", M.repeat_line)
    keys.on("shift+enter", M.skip)
    LoopInGameThreadWithDelay(INTERVAL_MS, function()
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] dialogue error: " .. tostring(err) .. "\n") end
    end)
end

return M
