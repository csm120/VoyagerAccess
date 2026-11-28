-- V switches between the ship view and the System Map. The game has no
-- keyboard binding for it, only the Ship and System buttons in the HUD's
-- navigation bar (ShowShipButton, ShowSystemButton, found 2026-10-11);
-- until then only tutorials switched views for Casey. V is unbound.

local speech = require("speech")
local screen = require("screen")

local M = {}

-- The navigation bar (WBP_NavigationBar_01_C in the HUD), set when the
-- game makes it (hook_bar below). Its buttons are its own fields
-- (ShowShipButton, ResearchButton, ...): read there, not by searching about
-- 490 buttons for their path (rule 42, header dump 2026-10-18).
local bar_path = nil
local function nav_bar()
    local b = bar_path and StaticFindObject(bar_path)
    if b and b:IsValid() then return b end
    return nil
end

local function find(name)
    local b = nil
    -- The tutorial library's button is beside the bar, in the HUD's
    -- notifications (WBP_Notifications.WBP_Tutorial_Button: the question mark
    -- a sighted player clicks to read any tutorial again; it opened the
    -- library in the VM, 2026-11-07).
    if name == "TutorialButton" then
        pcall(function()
            for _, n in ipairs(FindAllOf("WBP_Notifications_C") or {}) do
                if n:IsValid() and n:GetFullName():find(" /Engine/Transient.", 1, true) then b = n.WBP_Tutorial_Button end
            end
        end)
        if b and b:IsValid() and screen.shown(b) then return b end
        return nil
    end
    local bar = nav_bar()
    pcall(function() b = bar[name] end)
    if b and b:IsValid() and screen.shown(b) then return b end
    return nil
end

function M.toggle()
    -- Not behind a window: V switched the map behind an open Research
    -- Report (VM, 2026-10-15).
    if require("focus").virtual_window_open() then
        speech.say("Close the window first", true)
        return
    end
    local to_map = require("ship").active()
    local b = find(to_map and "ShowSystemButton" or "ShowShipButton")
    if not b then
        speech.say("Cannot switch view here", true)
        return
    end
    b:HandleButtonPressed()
    b:HandleButtonReleased()
    b:HandleButtonClicked()
    -- Said at once: the full line waits for the view to settle, about 1.6 s
    -- after the key (VM log, 2026-10-17), and a player found the keys
    -- sluggish (forum, TheRev, 2026-10-17). help.lua then says only what is
    -- selected: the next view it announces is this one (no time window).
    M.toggled = to_map and "system" or "ship"
    speech.say(to_map and "System map" or "Ship view", true)
end

-- N: the navigation bar as a list (Casey, 2026-10-11: "how do I get to the
-- other tabs from ship view?"). The bar (WBP_NavigationBar) takes only the
-- mouse and is shown only in the ship and map views. Up and Down choose,
-- Enter presses, Backspace closes the list. N is unbound in the game.
local NAV = {
    { "Ship view", "ShowShipButton" }, { "System map", "ShowSystemButton" },
    { "Sector map", "ShowSectorButton" }, { "Overview", "OverviewButton" },
    { "Research", "ResearchButton" }, { "Wait one cycle", "WaitOneCycleButton" },
    { "Incoming calls", "IncomingCallsButton" }, { "Sector switch, leave for the next sector", "SectorSwitchButton" },
    -- tr.word: Tutorials
    { "Tutorials", "TutorialButton" },
    -- Q Trials only: opens Leave Sector (missing from N, VM, 2026-10-14)
    { "Leave sector", "SandboxExitSector" },
}
local nav_items, nav_index = nil, nil

-- Only in the ship view and the System Map, where the bar lives: opened
-- over the game menu, Up and Down moved both the list and the menu, and the
-- two talked over each other (2026-10-11).
local function nav_place()
    local ctx = require("help").context()
    return ctx == "ship" or ctx == "system"
end

function M.nav_open()
    if nav_items and not nav_place() then nav_items = nil end
    return nav_items ~= nil
end

local nav_text   -- below; nav_where needs it (it was nil here, so I said nothing, 2026-10-21)

-- An item's name in the game's language. "Research" is off the line-wide
-- pass, which turned the game's own German texts into other words
-- (firefly82, 2026-10-24), so it is looked up here, where the mod says it.
local function label(it)
    -- tr.word: Research
    return require("tr").word(it[1])
end

-- For I (where am I) while N is open: it described the map behind the
-- list (VM, 2026-10-14).
function M.nav_where()
    if not M.nav_open() then return nil end
    local it = nav_items[nav_index]
    if not it then return "Navigation list" end
    return string.format("Navigation list. %s, %d of %d", nav_text(it), nav_index, #nav_items)
end

-- The Ship button carries the game's count of rooms waiting with a prompt
-- (RoomPromptIndicator, a side mission icon and "1" on the Sector Map; the
-- mod never said it, map parity audit, 2026-10-21).
-- The Research button's progress bars (WBP_NavigationBar_Button_01): one
-- pair for research, one for analysis, each an active bar and a paused bar
-- in its own border, shown only while one runs (header dump, 2026-10-28).
-- A sighted player sees the bar fill and turn to its paused look; the N list
-- said only "Research", and Casey did not know his research was running
-- (2026-11-25). The bar shows no name, so none is said (parity rule).
local function bar_words(btn, active_border, active_bar, paused_border, paused_bar)
    local screen = require("screen")
    local function shown_pct(border, bar)
        local ok, pct = pcall(function()
            local b, p = btn[border], btn[bar]
            if not (b and b:IsValid() and screen.shown(b) and p and p:IsValid() and screen.shown(p)) then return nil end
            return math.floor(p.Percent * 100 + 0.5)
        end)
        return ok and pct or nil
    end
    local pct = shown_pct(active_border, active_bar)
    if pct then return "in progress, " .. pct .. "%" end
    pct = shown_pct(paused_border, paused_bar)
    if pct then return "paused, " .. pct .. "%" end
    return nil
end

function M.research_progress(btn)
    if not (btn and btn:IsValid()) then return nil end
    local out = {}
    local r = bar_words(btn, "Border_inProgress", "ResearchBar_active", "Border_paused", "ResearchBar_paused")
    if r then out[#out + 1] = r end
    local a = bar_words(btn, "AnalysisBorder_inProgress", "AnalysisBar_active", "AnalysisBorder_paused", "AnalysisBar_paused")
    if a then out[#out + 1] = "analysis " .. a end
    if #out == 0 then return nil end
    return table.concat(out, ", ")
end

function nav_text(it)
    local text = label(it)
    if it[2] == "ShowShipButton" then
        local bar = nav_bar()
        local okp, s = pcall(function() return require("ship").prompt_words(bar.RoomPromptIndicator) end)
        if okp and s then text = text .. ", " .. s end
    elseif it[2] == "ResearchButton" then
        local bar = nav_bar()
        local okp, s = pcall(function() return M.research_progress(bar.ResearchButton) end)
        if okp and s then text = text .. ", " .. s end
    end
    return text
end

local function say_nav()
    local it = nav_items[nav_index]
    speech.say(string.format("%s, %d of %d", nav_text(it), nav_index, #nav_items), true)
end

function M.nav_toggle()
    if nav_items then
        nav_items = nil
        speech.say("Closed", true)
        return
    end
    if not nav_place() then
        speech.say("Navigation is available in the ship view and the System Map", true)
        return
    end
    local items = {}
    for _, it in ipairs(NAV) do
        local b = find(it[2])
        if b and b:GetIsEnabled() then items[#items + 1] = it end
    end
    if #items == 0 then
        speech.say("Navigation is not available here", true)
        return
    end
    nav_items, nav_index = items, 1
    say_nav()
end

function M.nav_step(dir)
    local i = nav_index + dir
    if nav_items[i] then nav_index = i end
    say_nav()
end

function M.nav_edge(last)
    nav_index = last and #nav_items or 1
    say_nav()
end

function M.nav_close()
    if not nav_items then return false end
    nav_items = nil
    speech.say("Closed", true)
    return true
end

-- The calls list's buttons on screen (WBP_IncomingCallButtonWidget fills its
-- IncomingCallButtonContainer with one WBP_IncomingCall_List_Button per call).
local function shown_calls()
    local list = {}
    for _, c in ipairs(FindAllOf("WBP_IncomingCall_List_Button_C") or {}) do
        if c:IsValid() and c:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(c) then
            list[#list + 1] = c
        end
    end
    return list
end

-- One call in the list: answered at once, as Enter on it does (Casey,
-- 2026-11-27: "I've never seen more than 1 option"). Two or more stay a
-- list, read by focus.lua, and Enter answers the one heard (two calls were
-- seen once, 2026-10-24). The list may come up a tick after the bar's
-- click, so it is looked for a few times. A click the game ignores leaves
-- the list open with focus on the call, where Enter still answers it.
-- Stops once the player has moved on (another key: the pause menu or any
-- other window opened by the player takes one), and answers only while the
-- journey counts exactly one waiting call (GPT and Fable reviews,
-- 2026-11-27: a row behind a new menu could still be clicked, and
-- "Incoming calls" said over it late). Not help.context: the call list
-- itself may read as a window there.
local function moved_on(key_at)
    local ok, keys = pcall(require, "keys")
    return ok and key_at ~= nil and keys.key_count ~= key_at
end

local function waiting_calls()
    local n = nil
    pcall(function()
        local j = FindFirstOf("STVJourneySubsystem")
        if j and j:IsValid() then n = j:GetIncomingCallsNum() end
    end)
    return n
end

local function answer_single(tries, key_at)
    if moved_on(key_at) then return end
    local ok, list = pcall(shown_calls)
    if ok and #list == 1 and waiting_calls() == 1 then
        local c = list[1]
        local t = ""
        pcall(function() t = c.NotificationText:GetText():ToString() end)
        print("[VoyagerAccess] view: H answers the only call\n")
        speech.say(string.format("Incoming call: %s", t ~= "" and t or require("tr").word("unnamed")), true)
        pcall(function()
            c:HandleButtonPressed()
            c:HandleButtonReleased()
            c:HandleButtonClicked()
        end)
        return
    end
    if ok and #list > 1 then return end
    if tries > 0 then
        ExecuteInGameThreadWithDelay(100, function() answer_single(tries - 1, key_at) end)
    else
        -- No list came: say what was pressed, as before.
        speech.say(label({ "Incoming calls" }), true)
    end
end

-- H: a waiting call, as a click on the bar's call button does (Casey,
-- 2026-10-26: so many calls, and each took N, three Downs and Enter). One
-- call is answered at once; with more, the list opens and Enter answers.
function M.calls_key()
    if not nav_place() then
        -- Over an event window on the map this sounded like "no" while
        -- a call was waiting under it (Casey, 2026-10-27): say that it is.
        -- The journey's own call count: under a window the bar is hidden,
        -- and its button reads enabled with no call (VM, 2026-10-27).
        local calls = 0
        pcall(function()
            local j = FindFirstOf("STVJourneySubsystem")
            if j and j:IsValid() then calls = j:GetIncomingCallsNum() end
        end)
        -- Not in a conversation: the call being answered may still count
        -- until it ends (Fable review).
        if type(calls) == "number" and calls > 0 and not require("dialogue").active() then
            speech.say("A call is waiting; H answers it from the ship view or the System Map", true)
        else
            speech.say("Calls are answered in the ship view or the System Map", true)
        end
        return
    end
    local b = find("IncomingCallsButton")
    if not (b and b:GetIsEnabled()) then
        -- The bar hidden under a window (a report over the map) is not
        -- "no call" (Fable review, 2026-10-26).
        local bar = nav_bar()
        if bar and not screen.shown(bar) then speech.say("Close the window first", true) return end
        speech.say("No incoming call", true)
        return
    end
    nav_items = nil
    print("[VoyagerAccess] nav: Incoming calls (H)\n")
    b:HandleButtonPressed()
    b:HandleButtonReleased()
    b:HandleButtonClicked()
    local okk, keys = pcall(require, "keys")
    answer_single(10, okk and keys.key_count or nil)
end

-- Sector switch leaves the sector at once: active missions were cancelled
-- with no warning heard (State of Flux, VM, 2026-10-15). The game's own
-- warning is on its hover; the first Enter says it and a second Enter
-- within a few seconds leaves.
local switch_armed_until = -100

function M.nav_enter()
    local it = nav_items[nav_index]
    if it[2] == "SectorSwitchButton" and os.clock() > switch_armed_until then
        switch_armed_until = os.clock() + 8
        speech.say("Leaving the sector cancels all active missions, and heroes marked unavailable are lost. "
            .. "Press Enter again to leave.", true)
        return
    end
    nav_items = nil
    local b = find(it[2])
    if not b then
        speech.say(label(it) .. " is not available here", true)
        return
    end
    print("[VoyagerAccess] nav: " .. it[1] .. "\n")
    -- Wait One Cycle is a hold button (bRequiresHold): a tap did nothing
    -- (2026-10-14). Hold it as the away mission Confirm is held.
    local ok, hold = pcall(function() return b.bRequiresHold end)
    if ok and hold then
        speech.say(label(it) .. ", holding", true)
        b:HandleButtonPressed()
        local name = it[2]
        ExecuteInGameThreadWithDelay(require("screen").hold_ms(b), function()
            pcall(function()
                local nb = find(name)
                if nb then nb:HandleButtonReleased() end
                print("[VoyagerAccess] nav: released " .. name .. "\n")
            end)
        end)
        return
    end
    b:HandleButtonPressed()
    b:HandleButtonReleased()
    b:HandleButtonClicked()
    -- Ship view and System map are announced by help.lua once they are up.
    -- The Sector map is named here, and help.lua then says only what is
    -- selected: "Sector map" came twice (VM, 2026-10-21).
    if it[2] == "ShowSectorButton" then M.nav_named, M.nav_named_at = "Sector map", os.clock() end
    if it[2] ~= "ShowShipButton" and it[2] ~= "ShowSystemButton" then speech.say(label(it), true) end
end

-- Left and Right switch the Overview's tabs, as in a room window; the new
-- tab is read by popups.lua when its text changes. True when it did.
-- The Overview's Heroes tab: a grid of hero cards (WBP_Hero_InfoCardButton,
-- plain UMG Buttons the mod's button lists do not take) and the selected
-- hero's details. Only the first hero's details could be heard (Q Trials,
-- VM, 2026-10-15). Up and Down walk the cards; each step selects the card as
-- a click does (its own OnButtonClicked event) and reads the details.
local hero_index = nil

local function heroes_panel()
    for _, w in ipairs(FindAllOf("WBP_Hero_Overview_C") or {}) do
        if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(w) then return w end
    end
    return nil
end

function M.heroes_open()
    local open = heroes_panel() ~= nil
    if not open then hero_index = nil end
    return open
end

local function texts_in(prefix)
    local out, seen = {}, {}
    for _, cls in ipairs({ "TextBlock", "RichTextBlock" }) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            local tp = t:IsValid() and t:GetFullName():match("^%S+%s+(.+)$")
            if tp and not seen[tp] and tp:sub(1, #prefix) == prefix and screen.shown(t) then
                seen[tp] = true
                local ok, s = pcall(function() return t:GetText():ToString() end)
                if ok then out[tp:match("([%w_]+)$")] = require("text").prep(s):gsub("<[^>]*>", "") end
            end
        end
    end
    return out
end

local function hero_cards()
    local panel = heroes_panel()
    if not panel then return {} end
    local pp = panel:GetFullName():match("^%S+%s+(.+)$") .. "."
    -- In the campaign the cards are created with the game instance as their
    -- outer, so their path is not under the panel ("0 heroes", VM,
    -- 2026-10-16); climb the parents, crossing widget trees, instead.
    local panel_path = pp:sub(1, -2)
    local cards = {}
    for _, c in ipairs(FindAllOf("WBP_Hero_InfoCardButton_C") or {}) do
        local cp = c:IsValid() and c:GetFullName():match("^%S+%s+(.+)$")
        if cp and screen.inside(c, panel_path) and screen.shown(c) then
            local parent, idx, pidx = nil, 0, 0
            pcall(function()
                parent = c:GetParent()
                idx = parent:GetChildIndex(c)
                pidx = parent:GetParent():GetChildIndex(parent)
            end)
            cards[#cards + 1] = { w = c, path = cp, key = pidx * 1000 + idx }
        end
    end
    table.sort(cards, function(a, b) return a.key < b.key end)
    return cards
end

local function card_text(c)
    local parts = {}
    for _, cls in ipairs({ "TextBlock" }) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            local tp = t:IsValid() and t:GetFullName():match("^%S+%s+(.+)$")
            if tp and tp:sub(1, #c.path + 1) == c.path .. "." and screen.shown(t) then
                local ok, s = pcall(function() return t:GetText():ToString() end)
                -- Skill values without their icons ("25, 29") are left out.
                if ok and s ~= "" and not s:match("^[%d%s%+%-]+$") then parts[#parts + 1] = s end
            end
        end
    end
    return table.concat(parts, ", ")
end

local function hero_details()
    local panel = heroes_panel()
    if not panel then return "" end
    local by = texts_in(panel:GetFullName():match("^%S+%s+(.+)$") .. ".")
    local out = {}
    local function add(k, label)
        local v = by[k]
        if v and v ~= "" then out[#out + 1] = (label and (label .. ": ") or "") .. v:gsub("%.%s*$", "") end
    end
    add("SelectedHeroTrait_1", "Trait")
    add("SelectedHeroTrait_2", "Trait")
    add("SelectedHeroCondition_1")
    add("SelectedHeroCondition_2")
    add("SelectedHeroLocation", "Location")
    -- "Passive Bonus" or "Combat Ability", as the header says.
    local head = by.CaptainBonusHeader_TXT
    if not head or head == "" then head = by.CombatAbilityHeader_TXT end
    add("AbilityTextBlock", (head and head ~= "") and head or "Bonus")
    add("SelectedHeroBiography")
    return table.concat(out, ". ") .. "."
end

function M.hero_count()
    return #hero_cards()
end

function M.hero_step(dir, edge)
    local cards = hero_cards()
    if #cards == 0 then return false end
    if edge then
        hero_index = dir < 0 and 1 or #cards
    else
        hero_index = math.max(1, math.min(#cards, (hero_index or 0) + dir))
    end
    local c = cards[hero_index]
    local name = card_text(c)
    -- The name first: the card's texts came out "Not recruited, Tuvok"
    -- (VM, 2026-10-17).
    name = (name:gsub("^([^,]*[Rr]ecruited), (.+)$", "%2, %1"))
    -- And "Rank 01, Neelix" (the same day).
    name = (name:gsub("^[Rr]ank 0*(%d+), (.+)$", "%2, rank %1"))
    pcall(function() c.w["BndEvt__WBP_Hero_InfoCardButton_Button_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature"](c.w) end)
    speech.say(string.format("%s, %d of %d", name ~= "" and name or require("tr").word("Hero"), hero_index, #cards), true)
    ExecuteInGameThreadWithDelay(250, function()
        pcall(function() speech.say(hero_details(), false) end)
    end)
    return true
end

-- Up and Down go line by line through the Overview's open tab, Home and
-- End to the ends, as in the C list (firefly82's review, 2026-10-19). The
-- lines are read again from the tab at each key, so a tab switch or a new
-- value is never a stale copy; the place starts over when the tab changes.
local ov = nil   -- { head = first line, index = n }

function M.overview_list_step(dir, edge)
    -- On the Q Trials tab focus is on the challenge levels (overview_tab),
    -- a real list whose details only they give: the game moves along it and
    -- focus.lua says each. Stepping these lines as well said two things for
    -- every Down ("Q Challenges, 2 of 5" and "Level 2, not active...", VM,
    -- 2026-10-21).
    local okc, cur = pcall(function() return require("focus").current_path() end)
    if okc and cur and cur:find("QChallengesPlaque", 1, true) then return false end
    local ok, lines = pcall(function() return require("popups").overview_lines() end)
    if not (ok and lines and #lines > 1) then
        ov = nil
        return false
    end
    if not ov or ov.head ~= lines[1] then ov = { head = lines[1], index = 0 } end
    if edge then
        ov.index = dir < 0 and 1 or #lines
    else
        ov.index = math.max(1, math.min(#lines, ov.index + dir))
    end
    speech.say(string.format("%s, %d of %d", lines[ov.index], ov.index, #lines), true)
    return true
end

-- Enter on a line says it again: a line does nothing, and Enter must not
-- reach the game's Close button behind it.
function M.overview_list_repeat()
    if not ov then return false end
    return M.overview_list_step(0)
end

function M.overview_tab(dir)
    -- The shown Overview from popups' record of open windows, and its own
    -- PreviousTabButton / NextTabButton (WBP_OverviewInfoWidget, CXX dump),
    -- not a search of every Overview and every button in the game.
    local w = require("popups").open_of({ WBP_OverviewInfoWidget_C = true })
    if not w then return false end
    local want = dir < 0 and "PreviousTabButton" or "NextTabButton"
    local okf, field = pcall(function() return w[want] end)
    for _, b in ipairs({ okf and field or nil }) do
        if b:IsValid() then
            b:HandleButtonPressed()
            b:HandleButtonReleased()
            b:HandleButtonClicked()
            -- Focus inside the Overview waits for the new tab's reading
            -- (focus.lua), then is said after it: on the Q Trials tab
            -- "Level 0, active: No Q Trial modifiers are activated, 1 of 11"
            -- came before "Overview, Q Trials tab" (VM, 2026-10-21). Said
            -- anyway if the tab is not read within 0.8 s.
            M.tab_hold_until = os.clock() + 0.8
            local hold = M.tab_hold_until
            ExecuteInGameThreadWithDelay(800, function()
                if M.tab_hold_until == hold then
                    M.tab_hold_until = 0
                    pcall(require("focus").reannounce)
                end
            end)
            -- After the new tab is in place: forgotten at once, the old tab
            -- was read again and the new one missed (VM, 2026-10-17).
            -- Only when the new tab has not been read already: its text
            -- changed, so the poll read it, and forgetting it then read
            -- every tab twice (firefly82, German game, 2026-10-18).
            local okb, before = pcall(require("popups").remembered, "WBP_OverviewInfoWidget_C")
            ExecuteInGameThreadWithDelay(400, function()
                pcall(function()
                    local popups = require("popups")
                    if not okb or popups.remembered("WBP_OverviewInfoWidget_C") == before then
                        popups.forget("WBP_OverviewInfoWidget_C")
                    end
                end)
            end)
            -- The game gets the same arrow: on the Q Trials tab it moved
            -- focus into the Q Modifier picker instead (VM, 2026-10-15). The
            -- tab is read as a whole, so the game's focus is parked.
            -- Except on the Q Trials tab, whose challenge levels are a list:
            -- parked there, Down went to CLOSE (VM, 2026-10-17). Its active
            -- level (the one not locked) takes focus.
            ExecuteInGameThreadWithDelay(150, function()
                local first, active = nil, nil
                for _, x in ipairs(FindAllOf("WBP_Sandbox_Setup_QChallengesPlaque_Overview_C") or {}) do
                    if x:IsValid() and x:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(x) then
                        first = first or x
                        if not x.IsLocked and not active then active = x end
                    end
                end
                local target = active or first
                if target then
                    pcall(function() target:SetFocus() end)
                else
                    pcall(require("focus").park_focus)
                end
            end)
            return true
        end
    end
    return true
end

-- A call coming in shows the Incoming Calls button on the navigation bar
-- and nothing else: the mod said nothing, the objective only said "Answer
-- the incoming distress call", and a forum player could not find how to
-- answer the array's hail in the first mission (2026-10-15). Said once when
-- the button appears, while the bar is up (ship view or System Map).
local call_waiting = false
-- Read from the bar's own IncomingCallsButton when the bar updates it
-- (UpdateIncomingCallButton), not by searching every button each second
-- (three searches over about 490 buttons a second; the mod's loops held the
-- game long enough to swallow keys, firefly82, 2026-10-21).
local function check_calls(bar)
    if not (bar and bar:IsValid() and screen.shown(bar)) then return end   -- bar not up
    local b = bar.IncomingCallsButton
    local waiting = b ~= nil and b:IsValid() and screen.shown(b)
    if waiting then
        local ok, en = pcall(function() return b:GetIsEnabled() end)
        waiting = not (ok and en == false)
    end
    if waiting and not call_waiting then
        print("[VoyagerAccess] view: incoming call waiting\n")
        pcall(function() require("calllisten").button_seen() end)
        -- A new hint key: the N wording was heard twice by now (hints.lua).
        speech.say("Incoming call." .. require("hints").text("call_h1", " To answer, press H."), false)
    end
    call_waiting = waiting
end

-- The navigation bar's own events (WBP_NavigationBar_01_C): OnViewChanged
-- from the game's event bus (proven 2026-10-16: "view 5 to 9" on V) and
-- UpdateIncomingCallButton. Hooked when the game makes the bar.
local bar_hooked = {}
local function hook_bar(path)
    local bar = StaticFindObject(path)
    if not (bar and bar:IsValid()) then return end
    if path:find("^/Engine/Transient%.") then bar_path = path end
    local cpath = bar:GetClass():GetFullName():match("^%S+%s+(.+)$")
    if not cpath then return end
    -- Each hook is marked only once it is in: a first try that failed (the
    -- class's functions not loaded yet) was marked anyway and never tried
    -- again, so after that load no view change reached the mod and the view
    -- was not said until some window opened (VM, 2026-10-21).
    local done = bar_hooked[cpath] or {}
    bar_hooked[cpath] = done
    if done.calls and done.view then check_calls(bar) return end
    local function after(fn)
        return function(ctx, payload)
            local okp, p = pcall(function() return ctx:get():GetFullName():match("^%S+%s+(.+)$") end)
            if not (okp and p) then return end
            -- The view the game is changing to, from the event itself
            -- (STVViewChangePayload:GetTarget, ESTVGameViewType: 5
            -- ConstructionSideview, 9 SystemOverview; "view 5 to 9" in the
            -- probe of 2026-10-16). At the event the ship view's input is not
            -- applied yet, so asking whether it is active said "no" and the
            -- arrival was not announced (firefly82's test, 2026-10-21).
            local target = nil
            pcall(function() target = payload:get():GetTarget() end)
            -- Pre hooks: the bar has applied the change on the next tick.
            ExecuteInGameThread(function()
                pcall(function()
                    local b = StaticFindObject(p)
                    if b and b:IsValid() then fn(b, target) end
                end)
            end)
        end
    end
    if not done.calls then
        done.calls = pcall(RegisterHook, cpath .. ":UpdateIncomingCallButton", after(check_calls))
    end
    if not done.view then
        done.view = pcall(RegisterHook, cpath .. ":OnViewChanged", after(function(b, target)
            -- An error in the call check must not skip the view check.
            local okc, errc = pcall(check_calls, b)
            if not okc and not done.calls_logged then
                done.calls_logged = true
                print("[VoyagerAccess] view: call check failed: " .. tostring(errc) .. "\n")
            end
            local VIEWS = { [5] = "ship", [9] = "system" }
            require("help").view_check(type(target) == "number" and (VIEWS[target] or "other") or nil)
        end))
    end
    print("[VoyagerAccess] view: navigation bar events " .. ((done.calls and done.view) and "hooked" or "not all hooked yet") .. "\n")
    -- Tried again a second later, up to five times, by path.
    if not (done.calls and done.view) and (done.tries or 0) < 5 then
        done.tries = (done.tries or 0) + 1
        ExecuteInGameThreadWithDelay(1000, function() pcall(hook_bar, path) end)
    end
    check_calls(bar)
end

M.tab_hold_until = 0
function M.install()
    require("keys").on("v", M.toggle)
    require("keys").on("n", M.nav_toggle)
    require("keys").on("h", M.calls_key)
    -- The new Overview tab has been read: the focused item now (overview_tab).
    require("popups").on_read(function(_, cls)
        if cls == "WBP_OverviewInfoWidget_C" and os.clock() < M.tab_hold_until then
            M.tab_hold_until = 0
            pcall(require("focus").reannounce)
        end
    end)
    -- Escape just after a tab switch: no tab reading comes, and the hold
    -- would keep every focus look quiet until it ran out (Fable review).
    require("popups").on_close(function(_, cls)
        if cls == "WBP_OverviewInfoWidget_C" then M.tab_hold_until = 0 end
    end)
    require("popups").on_widget("WBP_NavigationBar_01_C", hook_bar)
    for _, b in ipairs(FindAllOf("WBP_NavigationBar_01_C") or {}) do
        local p = b:IsValid() and b:GetFullName():match("^%S+%s+(.+)$")
        if p and p:find("^/Engine/Transient%.") then pcall(hook_bar, p) end
    end
end

return M
