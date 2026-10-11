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
local WINDOW_CLASSES = { "WBP_Dialogue_Window_C", "WBP_Dialogue_Window_SideView_C", "WBP_Dialogue_Window_Sector_C" }

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
    local card = (title ~= "" and title .. ". " or "") .. body
    if body == "" or card == last_popup then return end
    last_popup = card
    speak_story(card)
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
    local speaker = plain(w.DialogueSpeakerText:GetText():ToString())
    if speaker == PLACEHOLDER_SPEAKER then return end
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

function M.is_choice(path)
    return path ~= nil and path:find("WBP_Dialogue_Choice_Sector_C_%d+%.") ~= nil
end

function M.choice_label(path)
    local cpath = path:match("^(.-WBP_Dialogue_Choice_Sector_C_%d+)")
    local c = cpath and StaticFindObject(cpath)
    if not (c and c:IsValid()) then return nil end
    local parts = {}
    local wording = ""
    pcall(function() wording = text_of(c.RightButton.Choice) end)
    wording = plain(wording):gsub("^%[Optional%]%s*", "Optional: ")
    if wording ~= "" then parts[#parts + 1] = wording end
    -- The requirement widget is not a named member, so find its text by path.
    local req = ""
    local want = cpath .. "."
    for _, cls in ipairs({ "TextBlock", "RichTextBlock" }) do
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
        req = plain(req):gsub("^%[", ""):gsub("%]$", ""):gsub(" %- Chance:", ", chance")
        parts[#parts + 1] = (unmet and "Needs " or "") .. req
    end
    local reward = ""
    pcall(function() reward = plain(text_of(c.RightButton.Reward)) end)
    if reward ~= "" then parts[#parts + 1] = reward end
    if #parts == 0 then return nil end
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    return table.concat(parts, ". ") .. "."
end

-- Other readers (tutorials, toasts) add their text for R to repeat.
function M.remember(text)
    last_spoken = text
end

function M.repeat_line()
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
