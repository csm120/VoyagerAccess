-- Reads the dialogue window (speaker and line) and lets Enter continue it.
-- The game maps dialogue Continue/Skip only to the left mouse button and the
-- gamepad (IMC_Dialogue_Map, the game's own key bindings), so the mod injects
-- the game's own input action. Proven 2026-10-10: injecting
-- IA_Dialogue_Continue advanced Janeway's lines.

local speech = require("speech")
local screen = require("screen")

local M = {}

-- The window's PATH, not the window: a UObject kept across ticks went stale
-- when the dialogue ended and crashed UE4SS (2026-10-10 21:55, symbolized).
local window_path = nil
local last_line = nil       -- last line spoken
local last_speaker = nil    -- the name said with the last line
local gone_since = nil      -- os.time() when the window closed
local stuck = { line = nil, count = 0 }   -- Enters on one finished line (M.continue)
local last_spoken = nil     -- "Speaker: line", kept after the window closes, for R
local continue_action = nil
-- Declared here because the window events use them; declared below them,
-- they saw empty globals and the second half of a one-Enter continue never
-- ran.
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

-- The open dialogue window comes from the game's own events, not from a
-- 150 ms scan of five classes (the mod's loops held the game long enough to
-- swallow keys; firefly82, 2026-10-21). The window census of 2026-10-21
-- showed every dialogue window calling ShowDialogue(CharacterRowName,
-- CharacterRow, DialogueLine) for each line, FinishShowingDialogueRow when
-- the line has been typed out, FinishShowChoices when its choices are up
-- and OnTriggerNextNode when it moves on; BP_OnActivated and
-- BP_OnDeactivated when it opens and closes. Every dialogue window class is
-- built on the native STVDialogueWindow, so new ones are found as the game
-- makes them (NotifyOnNewObject) and hooked on the class that defines each
-- event (ForEachFunction).
local NATIVE_WINDOW = "/Script/STVoyager.STVDialogueWindow"

-- Called once when the next FinishShowChoices has run (focus.lua's
-- returning choices). Defined before the window events that run them.
local choice_waiters = {}
function M.after_choices(fn) choice_waiters[#choice_waiters + 1] = fn end
local WINDOW_EVENTS = { ShowDialogue = "line", FinishShowingDialogueRow = "typed", FinishShowChoices = "choices",
    OnTriggerNextNode = "next", BP_OnActivated = "open", BP_OnDeactivated = "close", Destruct = "close",
    OnShowConsequences = "consequences_start", OnFinishedShowingConsequences = "consequences",
    OnFinishedShowConsequencesAnim = "consequences" }
-- The story card inside a window (WBP_Dialogue_Popup).
local POPUP_EVENTS = { BP_OnActivated = "card", SetContent = "card" }
local BASE = { ["/Script/UMG.UserWidget"] = true, ["/Script/UMG.Widget"] = true,
    ["/Script/CommonUI.CommonActivatableWidget"] = true, ["/Script/CommonUI.CommonUserWidget"] = true,
    ["/Script/UMG.Visual"] = true, ["/Script/CoreUObject.Object"] = true }

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

-- The game shows "Character Name" before the real speaker loads; Casey heard
-- "Character Name: Gentlemen, welcome to Voyager."
local PLACEHOLDER_SPEAKER = "Character Name"

local function find_window()
    if not window_path then return nil end
    local w = StaticFindObject(window_path)
    if w and w:IsValid() and screen.shown(w) then return w end
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
    return find_window()
end

-- True when the widget path is inside the dialogue window (a choice button).
function M.contains(path)
    return window_path ~= nil and path ~= nil and path:sub(1, #window_path + 1) == window_path .. "."
end

-- What R can go back through: the last messages, newest last. Pressing R
-- again within a few seconds goes one further back, so a tutorial cut off
-- by the next message can still be heard (forum player, 2026-10-16).
local history = {}
local back = 0            -- how far back the last R went
local last_r = -100       -- os.time() of the last R
local function push(text)
    if type(text) ~= "string" or text == "" then return end
    if history[#history] ~= text then
        history[#history + 1] = text
        if #history > 15 then table.remove(history, 1) end
    end
    back = 0
end

local function speak_story(text)
    last_spoken = text
    push(text)
    print("[VoyagerAccess] dialogue: " .. text .. "\n")
    speech.say_story(text)
end

-- Story cards ("Into the Badlands") are a popup inside the dialogue window,
-- with a title and a paragraph and their own Continue button.
local last_popup = nil
local function read_popup(w)
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

-- Focus on a story card's Continue (focus.lua): the card is read here if
-- the window's events missed it. A second "Seeking Sanctuary" card in
-- sector 11 was silent while focus sat on its Continue (VM, 2026-10-21):
-- the card was not shown yet when the window opened, and a card with no
-- dialogue line gets no later event. read_popup says nothing for a card
-- read already.
function M.card_focused(path)
    local wp = path:match("^(.-)%.WidgetTree_%d+%.WBP_Dialogue_Popup%.")
    if not wp then return end
    local w = StaticFindObject(wp)
    if not (w and w:IsValid() and screen.shown(w)) then return end
    window_path = wp
    read_popup(w)
end

local crumb = require("crumb")

-- One line, as ShowDialogue gives it: the speaker is the row's own name,
-- said only when the window shows a speaker (the away mission window keeps
-- its speaker field hidden, so a sighted player sees no name there;
-- 2026-10-11). The event's data replaces the old wait of up to about a
-- second for the name field ("Character Name" first, or the last line's
-- speaker for a moment; 2026-10-14 and 2026-10-15).
local function say_line(w, speaker, line)
    line = plain(line or "")
    if line == "" or line == last_line then return end
    local sp = w.DialogueSpeakerText
    local shows_speaker = sp and sp:IsValid() and screen.shown(sp)
    -- A conversation's first line comes while its window still fades in,
    -- so nothing in it counts as shown yet, and the line went without its
    -- speaker ("Captain, sensors are picking up something...", Harry Kim's;
    -- VM, 2026-10-21). Then the field's own visibility decides (the away
    -- mission window keeps it collapsed).
    if not shows_speaker and sp and sp:IsValid() and not screen.shown(w) then
        local okv, vis = pcall(function() return sp:IsVisible() end)
        shows_speaker = okv and vis
    end
    -- Still hidden on a call's first line, with the speaker known from the
    -- row: the field comes up a moment later ("Captain, we're being hailed
    -- on all emergency frequencies" was said without Harry Kim, whose name
    -- was on screen; VM, 2026-10-22). Looked at again 200 ms on, except in
    -- the away mission window, which keeps its speaker hidden for good.
    -- The same when the speaker is only the field's own text, still the
    -- placeholder: Tuvok's "Repairs in progress." went without his name
    -- (demo, VM, 2026-10-22).
    local row_who = (speaker and speaker ~= "" and plain(speaker) ~= PLACEHOLDER_SPEAKER) and plain(speaker) or nil
    local field_who = ""
    pcall(function() field_who = plain(sp:GetText():ToString()) end)
    local have_name = shows_speaker and (row_who ~= nil or (field_who ~= "" and field_who ~= PLACEHOLDER_SPEAKER))
    -- A field the shown window keeps hidden is no name to wait for.
    local field_vis = false
    pcall(function() field_vis = sp:IsVisible() end)
    -- The placeholder means the name is still loading (row and field both
    -- "Character Name" for Tuvok's second line, the field not yet visible).
    local loading = (speaker and plain(speaker) == PLACEHOLDER_SPEAKER) or field_who == PLACEHOLDER_SPEAKER
    local hidden_for_good = row_who == nil and not loading and screen.shown(w) and not field_vis
    if sp and sp:IsValid() and not have_name and not hidden_for_good then
        local okc, cls = pcall(function() return w:GetClass():GetFName():ToString() end)
        if okc and cls ~= "WBP_Dialogue_Window_AwayMission_C" then
            last_line = line
            local wp = path_of(w)
            -- Up to four looks 150 ms apart: one look at 200 ms still found
            -- the field empty when the window's class was hooked late (Tuvok's
            -- "Until completion, it would be logical..."; demo, VM, 2026-10-22).
            local function look(tries)
                local said = false
                pcall(function()
                    local w2 = StaticFindObject(wp)
                    local sp2 = w2 and w2:IsValid() and w2.DialogueSpeakerText
                    local shown, who = false, row_who
                    if sp2 and sp2:IsValid() then
                        local okv, vis = pcall(function() return sp2:IsVisible() end)
                        shown = screen.shown(sp2) or (okv and vis)
                        if not who then
                            local t = plain(sp2:GetText():ToString())
                            if t ~= "" and t ~= PLACEHOLDER_SPEAKER then who = t end
                        end
                    end
                    if (shown and who) or tries <= 1 or not (w2 and w2:IsValid()) then
                        said = true
                        if shown and who then last_speaker = who end
                        speak_story((shown and who) and (who .. ": " .. line) or line)
                    end
                end)
                if not said and tries > 1 then
                    ExecuteInGameThreadWithDelay(150, function() look(tries - 1) end)
                end
            end
            -- The placeholder can stay up to about a second (the wait this
            -- mod had before 0.3.68), so up to eight looks then.
            local tries = loading and 8 or 4
            ExecuteInGameThreadWithDelay(150, function() look(tries) end)
            return
        end
    end
    -- The call's row could not be read, or names nobody (a speaker's second
    -- line: Tuvok's "Until completion..." went without his name, shown on
    -- screen; demo, VM, 2026-10-22): the field the window shows.
    if (speaker == nil or plain(speaker) == "" or plain(speaker) == PLACEHOLDER_SPEAKER) and shows_speaker then
        speaker = sp:GetText():ToString()
    end
    speaker = shows_speaker and plain(speaker or "") or ""
    if speaker == PLACEHOLDER_SPEAKER then speaker = "" end
    last_speaker = speaker ~= "" and speaker or last_speaker
    last_line = line
    speak_story(speaker ~= "" and (speaker .. ": " .. line) or line)
end

-- The window's line as it shows it, for a window met already open (the mod
-- started, or its class was hooked just after it opened).
local function say_shown_line(w)
    local text = w.DialogueText
    if not (text and text:IsValid()) then return end
    local ok, target = pcall(function() return text.TargetText:ToString() end)
    local line = (ok and target and target ~= "") and target or text:GetText():ToString()
    local sp = w.DialogueSpeakerText
    local speaker = (sp and sp:IsValid()) and sp:GetText():ToString() or ""
    say_line(w, speaker, line)
end

local function on_window(kind)
    return function(ctx, row_name, row, line)
        local okp, p = pcall(function() return path_of(ctx:get()) end)
        if not (okp and p) then return end
        -- The line's own text and speaker, from the call itself.
        local speaker, text = nil, nil
        if kind == "line" then
            pcall(function() speaker = row:get().CharacterName:ToString() end)
            pcall(function() text = line:get():ToString() end)
        end
        -- Pre hooks: the window has applied the call on the next tick.
        ExecuteInGameThread(function()
            pcall(function()
                if kind == "close" then
                    if window_path == p then window_path = nil end
                    gone_since = os.time()
                    -- A Continue asked for during typing belongs to that line
                    -- only (GPT review, 2026-10-21: it could advance a later
                    -- line).
                    continue_pending = false
                    pcall(function() require("focus").request_check() end)
                    -- The ship view or map behind it is in front again.
                    pcall(function() require("help").view_check() end)
                    return
                end
                local w = StaticFindObject(p)
                if not (w and w:IsValid()) then return end
                window_path = p
                -- last_line is kept across a short close (a window on top),
                -- but not for long: a recurring conversation with the same
                -- line (the Doctor's "the infection rate is increasing!" in
                -- Medical Ethics) came back minutes later and was silent,
                -- waiting for Enter (VM, 2026-10-20). Gone 3 s or more, it
                -- is a new conversation, and the Enter count starts again.
                if gone_since and os.time() - gone_since >= 3 then
                    last_line, last_speaker = nil, nil
                    stuck.line, stuck.count = nil, 0
                end
                gone_since = nil
                crumb.at("dialogue: " .. kind)
                if kind == "line" then
                    continue_pending = false
                    if text then say_line(w, speaker, text) else say_shown_line(w) end
                elseif kind == "typed" or kind == "choices" or kind == "open" then
                    -- A line whose ShowDialogue came before the class was
                    -- hooked (the first window of its kind) is said now; a
                    -- line said already is not said again.
                    pcall(say_shown_line, w)
                    -- The game puts focus on the first choice inside
                    -- FinishShowChoices, so it is in place now, one tick
                    -- after the pre hook (firefly82's probe, 12 of 12 sets,
                    -- 2026-10-23): whoever waited for that is told.
                    if kind == "choices" then
                        local waiting = choice_waiters
                        choice_waiters = {}
                        for _, fn in ipairs(waiting) do pcall(fn) end
                    end
                    -- Enter during typing finished the line first; the
                    -- continue it asked for goes now that the line is done.
                    if kind == "typed" and continue_pending then
                        continue_pending = false
                        inject_continue()
                    end
                elseif kind == "consequences" or kind == "consequences_start" then
                    -- The away mission summary is final now (popups.lua).
                    if kind == "consequences" then pcall(function() require("awaymission").outcome_finished() end) end
                    pcall(function() require("popups").reread_class("WBP_AwayMissionOutcome_C") end)
                end
                read_popup(w)
                -- Choices up, gone or moved on: focus looks once, and the
                -- away mission's own reading of the window (awaymission.lua).
                pcall(function() require("focus").request_settle() end)
                pcall(function() require("awaymission").request_poll() end)
            end)
        end)
    end
end

local function on_popup(ctx)
    ExecuteInGameThread(function()
        pcall(function()
            local w = find_window()
            if w then read_popup(w) end
            require("focus").request_check()
        end)
    end)
end

local hooked_fn, class_done = {}, {}

-- Hooks the events in table events on the class in cls's chain that
-- defines each.
local function hook_events(cls, events, make)
    local taken, got = {}, {}
    local k = cls
    while k and k:IsValid() do
        local kpath = path_of(k)
        if not kpath or BASE[kpath] then break end
        k:ForEachFunction(function(f)
            local fname = f:GetFName():ToString()
            local kind = events[fname]
            if kind and not taken[fname] then
                taken[fname] = true
                local fpath = kpath .. ":" .. fname
                if not hooked_fn[fpath] then hooked_fn[fpath] = pcall(RegisterHook, fpath, make(kind)) end
                got[#got + 1] = fname
            end
        end)
        k = k:GetSuperStruct()
    end
    return got
end

local function hook_window(w)
    local cls = w:GetClass()
    local name = cls:GetFName():ToString()
    if not class_done[name] then
        class_done[name] = true
        local got = hook_events(cls, WINDOW_EVENTS, on_window)
        print("[VoyagerAccess] dialogue: " .. name .. " events: " .. table.concat(got, ", ") .. "\n")
    end
    pcall(function()
        local popup = w.WBP_Dialogue_Popup
        if popup and popup:IsValid() then
            local pname = popup:GetClass():GetFName():ToString()
            if not class_done[pname] then
                class_done[pname] = true
                hook_events(popup:GetClass(), POPUP_EVENTS, function() return on_popup end)
            end
        end
    end)
    -- Met already open: its line now.
    local p = path_of(w)
    if p and p:find("^/Engine/Transient%.") and screen.shown(w) then
        window_path = p
        pcall(say_shown_line, w)
        pcall(read_popup, w)
    end
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
    -- At either end the choice is said again, as in the mod's lists (Down
    -- on the last choice said nothing; VM, 2026-10-21).
    if not to then
        pcall(function() require("focus").reannounce() end)
        return true
    end
    -- On the next tick, not 200 ms later: the game never moved on these
    -- choices in the VM log ("moving to the next choice myself" on every
    -- key), and the wait was part of a 420 to 730 ms answer (2026-10-21).
    -- Where the game does move, it has by now (its key comes before the
    -- mod's), and the check below sees that.
    ExecuteInGameThread(function()
        pcall(function()
            local fc = StaticFindObject(from)
            local tc = StaticFindObject(to)
            -- Judged by the mod's own focus: on the bridge no button had
            -- keyboard focus at all, and a keyboard focus test moved one
            -- choice too many when the game had moved too. If the mod still
            -- has the same choice, nothing moved.
            -- Also when the game moved somewhere else: from an unavailable
            -- choice its own navigation skipped the next unavailable one
            -- (Down 5 to 7 and Up 6 to 4 of 7, Equinox, VM, 2026-10-18).
            local cur = require("focus").current_path() or ""
            if fc and fc:IsValid() and tc and tc:IsValid() and (cur == path or cur:sub(1, #to + 1) ~= to .. ".") then
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
    -- The choice's own texts, from its widget tree: searching every text in
    -- the game for its number and then its requirements (five searches of
    -- about 30 ms) made Up and Down on a choice take 420 to 730 ms to be
    -- answered (NVDA log times, VM, 2026-10-21; TheRev on the forum). The
    -- walk follows visibility down, as screen.shown did for each text.
    local number = ""
    local reqs, seen = {}, {}
    local want = cpath .. "."
    pcall(function()
        local T = { StaticFindObject("/Script/UMG.TextBlock"), StaticFindObject("/Script/UMG.RichTextBlock") }
        local order = 0
        screen.walk(c, function(t)
            local is_text = false
            for _, k in ipairs(T) do if k and k:IsValid() and t:IsA(k) then is_text = true end end
            if not is_text then return false end
            local tp = t:GetFullName():match("^%S+%s+(.+)$")
            if not (tp and tp:sub(1, #want) == want) or seen[tp] then return true end
            seen[tp] = true
            if tp:find("WBP_Dialogue_Requirement", 1, true) then
                order = order + 1
                reqs[#reqs + 1] = { text = text_of(t), idx = order, path = tp }
            elseif tp:find("LeftButton", 1, true) then
                local s = plain(text_of(t))
                if s:match("^%d+$") then number = s end
            end
            return true
        end)
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
    -- A choice can have several: "Enough resources to keep his people
    -- alive" needs Deuterium 1,200 and Food 1,200 (both unmet) and Dilithium
    -- 15, and only the last found, the met one, was read, so the reason it
    -- could not be taken was never heard (The Omega Directive, VM,
    -- 2026-10-20). Each one is read, in the order they are laid out (the
    -- walk above gathers them in the choice's own layout order).
    table.sort(reqs, function(a, b)
        if a.idx ~= b.idx then return a.idx < b.idx end
        return a.path < b.path
    end)
    for _, r in ipairs(reqs) do
        local req = r.text
        if req ~= "" and not req:find("^##") then
            local unmet = req:find("ColorNegative", 1, true) ~= nil
            -- "Phaser Control Room Level 1- Chance: 50% + 35%" has no space
            -- before the dash (Mirror, Mirror, VM, 2026-10-15).
            -- The game's own word for chance is kept, so this works in every
            -- language ("Erfolgschance: 70%" was read raw in German; firefly82's
            -- review, 2026-10-19): "Room Level 1 - Chance: 50%" becomes "Room
            -- Level 1, Chance 50%", and "Success Chance: 70%" (no room or hero
            -- needed; black hole, sector 7, 2026-10-18) "Success Chance 70%".
            req = plain(req):gsub("^%[", ""):gsub("%]$", ""):gsub("%s*%-%s*([^%d%-:]+):%s*(%d)", ", %1 %2")
            req = (req:gsub("^([^%d:]+):%s*(%d+%%)", "%1 %2"))
            -- The second number is the hero's bonus, shown highlighted: "chance
            -- 40% + 45%" read as a sum to work out (Jetrel, 2026-10-15).
            req = (req:gsub("(%d+%%) %+ (%d+%%)", "%1, plus %2 bonus"))
            parts[#parts + 1] = (unmet and "Needs " or "") .. req
        end
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
    push(text)
end

-- Who said the last line, for I.
function M.speaker()
    return last_speaker
end

function M.repeat_line()
    -- R again within 5 seconds: one message further back each time.
    local again = os.time() - last_r <= 5
    last_r = os.time()
    if again then
        back = back + 1
        local text = history[#history - back]
        if text then
            speech.say("Earlier: " .. text, true)
        else
            back = back - 1
            speech.say("No earlier message", true)
        end
        return
    end
    back = 0
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
-- at once, so finish the typing first and continue when the window says the
-- line has been shown (its FinishShowingDialogueRow), not on the next poll.
-- OPEN POINT: that the window calls it after SkipToLineEnd too is not seen
-- yet (the census saw it after lines that typed out by themselves).

-- Some lines do not take the continue action at all: Zilis's "Whoops...
-- HULL -3" in the Equinox chase took fourteen Enters and only Shift+Enter
-- (the hold to skip) moved it on (VM, 2026-10-18). After two Enters on the
-- same finished line, say so instead of staying silent (stuck is declared
-- at the top; a new conversation resets it).

function M.continue()
    local w = M.active()
    local text = w and w.DialogueText
    if text and text:IsValid() and not text:HasFinishedPlayingLine() then
        text:SkipToLineEnd(false)
        continue_pending = true
        return
    end
    local line = nil
    pcall(function() line = (w.DialogueSpeakerText:GetText():ToString()) .. "|" .. text:GetText():ToString() end)
    -- An Enter that went to another window on top (an away mission's result
    -- with the conversation waiting behind it) is not an Enter on this line:
    -- three of them said "This line does not move on with Enter" (VM,
    -- 2026-10-20).
    -- Nor is Enter on a choice (a choice that loops back to the same line,
    -- "Offer amends" then "Nevermind" in The Omega Directive, set it off),
    -- or with an away mission or another read-once window up (its result
    -- window has no focused button).
    local elsewhere, why = false, nil
    pcall(function()
        local cur = require("focus").current_path()
        local b = cur and StaticFindObject(cur)
        if b ~= nil and b:IsValid() and screen.shown(b) and not M.contains(cur) then why = "focus " .. tostring(cur:match("([^%.]+)$"))
        -- Only a choice on screen: after a pick the mod's focus record
        -- still names the hidden choice, every Enter on Zilis's stuck
        -- "Whoops... HULL -3" was taken for a choice, and the hint below
        -- never came (39 Enters, Equinox chase, VM, 2026-10-23).
        elseif M.is_choice(cur) and b ~= nil and b:IsValid() and screen.shown(b) then why = "choice"
        elseif require("awaymission").mission_active() then why = "away mission" end
        elsewhere = why ~= nil
        if elsewhere then return end
        -- Map markers and room prompts are windows too and always up.
        for _, p in ipairs(require("popups").open_windows()) do
            if not p:find("WBP_PoiEventWidget_C", 1, true) and not p:find("RoomPrompt", 1, true) then
                elsewhere, why = true, "window " .. tostring(p:match("([^%.]+)$"))
            end
        end
    end)
    if elsewhere then print("[VoyagerAccess] dialogue: Enter not counted for this line (" .. tostring(why) .. ")\n") end
    if elsewhere then
        stuck.line, stuck.count = nil, 0
    elseif line and line == stuck.line then
        stuck.count = stuck.count + 1
    else
        stuck.line, stuck.count = line, 1
    end
    if stuck.count >= 3 then
        stuck.count = 0
        speech.say("This line does not move on with Enter. Shift+Enter skips to the next choice.", true)
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
    -- Dialogue windows as the game makes them (no 150 ms scan), and those
    -- there already (a reload): hooked once per class.
    local ok, err = pcall(NotifyOnNewObject, NATIVE_WINDOW, function(o)
        local okp, p = pcall(function() return path_of(o) end)
        if not (okp and p) then return end
        ExecuteInGameThread(function()
            pcall(function()
                local w = StaticFindObject(p)
                if w and w:IsValid() then hook_window(w) end
            end)
        end)
    end)
    print("[VoyagerAccess] dialogue: new windows " .. (ok and "watched" or ("not watched: " .. tostring(err))) .. "\n")
    for _, cls in ipairs(WINDOW_CLASSES) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            if w:IsValid() and live(w) then pcall(hook_window, w) end
        end
    end
end

return M
