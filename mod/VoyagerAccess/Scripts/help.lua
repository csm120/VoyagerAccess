-- F1: the keys for the screen Casey is on. F1 is unused by the game
-- (the game's own key bindings). The "Press F1 for help" hint on each new kind
-- of screen was removed (Casey, 2026-10-11): it came back on every screen
-- after each mod reload and update.

local speech = require("speech")

local M = {}


-- Only the keys that work on the screen you are on (Casey, 2026-10-11:
-- F1 said too much; the general keys came after every screen's own).
local HELP = {
    cutscene = "Shift+Enter skips the cutscene.",
    story = "The story is read a line at a time. Shift+Enter skips it. R repeats the last line.",
    dialogue = "Enter continues. Shift+Enter skips to the choices. R repeats the last line. "
        .. "On choices, Up and Down move and Enter picks one.",
    ship = "Up and Down change deck. Left and Right move along the deck. Home and End go to the ends of the deck. "
        .. "Enter opens the room. V switches to the System Map. N lists the places to go, such as the Sector Map, the Overview and Research. H opens a waiting call, and Enter answers it. I says where you are; I twice lists the room's details. "
        .. "E is the room's quick action. Hold F to upgrade it, or T to demolish it.",
    system = "Up and Down move through the points of interest. Home and End go to the nearest and the farthest. "
        .. "Enter opens Scan and Set course. Backspace closes that list. V switches to the ship. N lists the places to go, such as the Sector Map, the Overview and Research. H opens a waiting call, and Enter answers it.",
    room = "Up and Down move between the buttons. Enter uses one. Left and Right switch tabs. Escape closes the room. "
        .. "Closing a hero list without choosing removes the hero.",
    event = "Up and Down move between the options. Where an option can take a hero, Left and Right choose one first. Enter picks the option. R reads the locked options.",
    mission = "Up and Down move through the choices, their heroes and Confirm. Home and End go to the first and last. "
        .. "Enter on a hero picks them for that choice, then Enter on its Confirm makes the choice. "
        .. "A hero below the skill needed can still succeed. After a result, Enter continues and R repeats it. "
        .. "Closing a hero list without choosing removes the hero.",
    settings = "Up and Down move between settings. Left and Right change the value. "
        .. "Home and End go to the first and last. Backspace goes back.",
    menu = "Up and Down move. Home and End go to the first and last. Enter selects. Backspace goes back.",
    difficulty = "Up and Down move. Home and End go to the first and last. Enter picks a mode and starts the game. "
        .. "In Custom, Left and Right change a setting, and Enter on Start Game holds it for you. Escape goes back.",
    qtrials = "Up and Down move. Home and End go to the first and last. Enter opens a slot's choices and picks one. "
        .. "In the hero list, Enter chooses or removes a hero, then Confirm. Left and Right change ship. "
        .. "Enter on Start Game holds it for you. Escape goes back.",
    combat = "Enter opens Orders; in the order wheel, Up and Down move and Enter picks. Space pauses and resumes. "
        .. "1 to 6 use the heroes' abilities. Left and Right pick a system and Up and Down move energy to it. "
        .. "I reads both ships and the energy. O reads the combat goal.",
    -- F1 in the tech tree and the Overview gave the general keys and the
    -- menu keys (VM, 2026-10-21).
    techtree = "Up and Down move. Home and End go to the first and last. "
        .. "Left and Right switch category; past the last one is every technology from A to Z. "
        .. "Enter opens the technology's panel, where Enter begins the research. Escape closes the panel, then the tree. "
        .. "Backspace closes the tree when no panel is open. R repeats the item.",
    overview = "Left and Right switch tabs. Up and Down go through the tab line by line. "
        .. "Home and End go to the first and last. On the Heroes tab, Up and Down choose a hero. Escape closes the Overview.",
    none = "O reads your objective. C reads resources, energy and morale. V switches between the ship and the System Map. N lists the places to go, such as the Sector Map, the Overview and Research. "
        .. "I says where you are. R repeats the last line; R again goes further back. Ctrl+F12 lists what is new in Voyager Access.",
}

-- Windows that open in front of a room or the map and hold the focused
-- button: offers, notices and confirmations (a Cargo Bay stock-loss warning
-- was named "Cargo Bay", VM, 2026-10-16).
-- The Overview too: switching from its Q Trials tab to Heroes left focus
-- on nothing for a moment, and "System map. Nothing selected" was said in
-- the middle of the Overview (VM, 2026-10-21).
local FRONT = { "WBP_MultipleChoiceWidget_C", "WBP_CommonInfoWidget_C", "WBP_CargoSwap_Confirmation_C",
    "WBP_ConfirmationWidget_C", "WBP_EngineeringOffice_Confirmation_C", "WBP_OverviewInfoWidget_C" }
local function front_window(wp)
    -- By class too: inside a room the warning is a named part
    -- ("...ResourceCapacityChangeConfirmWidget"), not a class in the path.
    local cls = ""
    -- Checked valid first: just after a report's Close, its path found a
    -- null object, and GetClass on it crashed the game (UE4SS reads the
    -- class at 0x10; pcall cannot catch that). 7 of 10 runs, VM, 2026-10-16.
    pcall(function()
        local o = StaticFindObject(wp)
        if o and o:IsValid() then cls = o:GetClass():GetFName():ToString() end
    end)
    for _, c in ipairs(FRONT) do
        if wp:find(c, 1, true) or cls == c then return true end
    end
    return false
end

-- Which kind of screen is in front, most specific first.
function M.context()
    local dialogue = require("dialogue")
    if dialogue.cutscene_playing() then return "cutscene" end
    -- Narration over a scene: the map behind it was announced as if it
    -- were in front (2026-10-14).
    if require("story").active() then return "story" end
    local screen = require("screen")
    -- The pause menu over a room: I said "Main Engineering, level 1,
    -- active. GAMMA" (demo, VM, 2026-10-15). Over an away mission it said
    -- "Dialogue" (VM, 2026-10-15), so it comes before dialogue.
    for _, w in ipairs(FindAllOf("WBP_PauseMenu_C") or {}) do
        if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(w) then
            return "menu"
        end
    end
    if dialogue.active() then return "dialogue" end
    if require("combat").active() then return "combat" end
    -- Event and room windows (2026-10-11): Escape closing a room is the
    -- game's own, tried with a real key press.
    for _, w in ipairs(FindAllOf("WBP_POIMultipleChoice_C") or {}) do
        if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(w) then
            return "event"
        end
    end
    -- An offer or notice over a room window: I said "Workshop, level 1,
    -- active. Continue." for the offer's Continue (VM, 2026-10-16). The
    -- window holding the focused button is the one in front.
    local over = false
    pcall(function()
        local cur = require("focus").current_path()
        local b = cur and StaticFindObject(cur)
        if not (b and b:IsValid()) then return end
        for _, wp in ipairs(require("popups").open_windows()) do
            if front_window(wp)
                and screen.inside(b, wp) then over = true end
        end
    end)
    -- The same window read as the mod's button list (the game's focus is
    -- empty when its buttons cannot take focus).
    pcall(function()
        local f = require("focus")
        local vw = f.virtual_active() and f.virtual_window()
        if vw and front_window(vw) then over = true end
    end)
    if over then return "menu" end
    -- Not a room left open behind the System Map (rooms.lua).
    if require("rooms").window_open() then return "room" end
    local focus = require("focus").context()
    -- A window read as the mod's own button list (a Research Report over
    -- the map): I said "System map" and N and V worked on the map behind it
    -- (full game, VM, 2026-10-15).
    if not focus and require("focus").virtual_window_open() then focus = "menu" end
    if require("ship").active() and not focus then return "ship" end
    if require("system").active() and not focus then return "system" end
    return focus or "none"
end

local function overview_open()
    for _, w in ipairs(FindAllOf("WBP_OverviewInfoWidget_C") or {}) do
        if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then
            return true
        end
    end
    return false
end

function M.say_help()
    local ctx = require("awaymission").keys_active() and "mission"
        or (require("techtree").open() and "techtree")
        or (overview_open() and "overview")
        or M.context()
    speech.say((HELP[ctx] or HELP.none) .. " Control F1 lists every key.", true)
end

-- I: where am I (L until 0.3.6: the game opens Leave Sector on L in Q Trials). The kind of screen and what is selected on it, read the
-- way the arrows read it (Casey, 2026-10-11: after entering a room or
-- restarting you do not know where you are). Not Shift+Up: the game also
-- gets the arrow and would move focus. L is unbound in every context
-- (the game's own key bindings).
local PLACES = { cutscene = "Cutscene", story = "Story", dialogue = "Dialogue", ship = "Ship view", system = "System map",
    room = "Room window", event = "Point of interest", settings = "Settings", menu = "Menu", none = "Game",
    difficulty = "Difficulty", qtrials = "Q Trials setup",
    combat = "Combat" }

-- I pressed again within a second and a half: the details of what you are
-- on, as a list (Casey, 2026-10-19). For now the ship view's room.
-- Wall-clock seconds: os.clock() is the game's processor time, which ran
-- far faster than real time and never saw two presses as close (VM).
-- Superseded 2026-10-21: measured in the VM in play, os.clock() advanced
-- 21.7 s while the wall clock advanced 22 s, so it is wall time there;
-- os.time() here still works and is kept.
local last_i = -100
function M.say_where()
    -- Whole seconds only, so "within 2" is one to three seconds.
    local again = os.time() - last_i <= 2
    last_i = os.time()
    if again and M.context() == "ship" and not require("resources").list_open()
        and not require("ship").list_open() then
        last_i = -100
        return require("ship").details()
    end
    local away = require("awaymission")
    local parts = {}
    local tree = require("techtree").where() or require("view").nav_where()
    if tree then
        parts[1] = tree
    elseif away.keys_active() then
        parts[1] = "Away mission"
        parts[2] = away.mission_where()
    else
        local ctx = M.context()
        parts[1] = PLACES[ctx] or "Game"
        if ctx == "system" and require("system").sector() then parts[1] = "Sector map" end
        -- An event by its own name ("Ecosphere Planet"), not "Point of
        -- interest" (VM, 2026-10-16).
        if ctx == "event" then
            pcall(function()
                for _, w in ipairs(FindAllOf("WBP_POIMultipleChoice_C") or {}) do
                    if w:IsValid() and require("screen").shown(w) then
                        local h = w.Header_Text:GetText():ToString()
                        if h and h ~= "" then parts[1] = h end
                    end
                end
            end)
        end
        if ctx == "room" then
            for _, w in ipairs(FindAllOf("WBP_RoomManagementV2_C") or {}) do
                if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then
                    local head = require("rooms").window_text(w:GetFullName():match("^%S+%s+(.+)$"))
                    parts[1] = head:match("^[^%.]+") or parts[1]
                end
            end
            parts[2] = require("focus").current_label()
        elseif ctx == "ship" then
            parts[2] = require("ship").where() or "No room selected"
        elseif ctx == "system" then
            parts[2] = require("system").where() or "Nothing selected"
        elseif ctx == "dialogue" then
            -- I said only "Dialogue." (VM, 2026-10-16): the focused choice,
            -- or who is speaking; R repeats the line itself.
            local label = require("focus").current_label()
            -- An away mission challenge's result said "Dialogue. R repeats
            -- the line." (VM, 2026-10-16).
            local result = nil
            pcall(function()
                for _, r in ipairs(FindAllOf("WBP_AwayMission_ChallengeResult_C") or {}) do
                    if r:IsValid() and r:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(r) then
                        result = r.MissionResult_Text:GetText():ToString()
                    end
                end
            end)
            -- An empty one is shown during the mission's opening story, and
            -- I said just "Away mission result." (demo, VM, 2026-10-21).
            -- Any text, not letters: %a misses Russian, Japanese and Chinese
            -- (GPT review, 2026-10-21).
            if result and result:find("%S") then
                parts[1] = "Away mission result"
                parts[2] = result
                parts[3] = require("hints").fresh("r_result") and "R repeats it, Enter continues" or nil
            elseif label and label:find("^Choice %d") then
                parts[2] = label
            else
                local who = require("dialogue").speaker()
                -- A story card keeps the last line's speaker ("Dialogue with
                -- Harry Kim" over Verdant World, VM, 2026-10-16).
                -- Only while the card is up: focus stays on its hidden
                -- Continue afterwards, and the lines after it lost their
                -- speaker (Sobras, VM, 2026-10-16).
                local cur = require("focus").current_path() or ""
                if cur:find("WBP_Dialogue_Popup", 1, true) then
                    local b = StaticFindObject(cur)
                    if b and b:IsValid() and require("screen").shown(b) then who = nil end
                end
                if who and who ~= "" then parts[1] = "Dialogue with " .. who end
                -- A story card has no speaker, only its Continue: I said
                -- just "Dialogue. R repeats the line." (VM, 2026-10-16).
                if not (who and who ~= "") and label and label ~= "" then parts[#parts + 1] = label end
                -- Only the first two times in a session: said with every
                -- conversation, it broke into the story (Casey, 2026-10-19:
                -- "once or twice when they come up is fine").
                if require("hints").fresh("r_line") then parts[#parts + 1] = "R repeats the line" end
            end
        elseif ctx == "cutscene" or ctx == "story" then
            parts[2] = nil
        elseif ctx == "combat" then
            -- An open order wheel first, then the ships.
            local label = require("focus").current_label()
            if label and label ~= "" then parts[2] = label end
            parts[#parts + 1] = require("combat").status()
        else
            -- A window read as the mod's button list: its title, not "Menu"
            -- ("Menu. CLOSE, 1 of 2" over a Construction Report, demo, VM,
            -- 2026-10-15).
            local f = require("focus")
            local win = ctx == "menu" and f.virtual_active() and f.virtual_window()
            if win then
                local ok, t = pcall(function() return require("popups").text_under(win) end)
                local title = ok and t and t:match("^([^%.:]+)")
                -- A notice starts with who sends it, so its title was only a
                -- name: "Lieutenant Lani. CLOSE" (VM, 2026-10-16). Add what
                -- it is about.
                if title and win:find("WBP_CommonInfoWidget_C", 1, true) then
                    local about = t:match("^[^%.]+%.%s*([^%.!]+)")
                    if about and about ~= "" and #title < 40 and #about < 80 and about ~= about:upper() then
                        title = title .. ". " .. about
                    end
                end
                if title and title ~= "" then parts[1] = title end
            end
            -- A window the focused button sits in, when it is not a list:
            -- a mission offer said only "Menu. Acknowledged." (Q Trial, VM,
            -- 2026-10-16). Its title, as for the lists above.
            if parts[1] == "Menu" and ctx == "menu" then
                pcall(function()
                    local cur = f.current_path()
                    local b = cur and StaticFindObject(cur)
                    if not (b and b:IsValid()) then return end
                    local screen = require("screen")
                    for _, wp in ipairs(require("popups").open_windows()) do
                        if front_window(wp)
                            and screen.inside(b, wp) then
                            local t = require("popups").text_under(wp)
                            local title = t and t:match("^([^%.:]+)")
                            if title and title ~= "" then parts[1] = title end
                            return
                        end
                    end
                end)
            end
            parts[2] = f.current_label()
            -- The team screen said "Menu" (demo, VM, 2026-10-15).
            if parts[1] == "Menu" and parts[2] and parts[2]:find("^Away team slot") then parts[1] = "Away team" end
        end
    end
    local out = {}
    -- tr.word: Menu | Game | Story
    if parts[1] then parts[1] = require("tr").word(parts[1]) end
    for _, p in ipairs(parts) do
        if p and p ~= "" then out[#out + 1] = (p:gsub("%.%s*$", "")) end
    end
    -- A trip under way, wherever L is pressed (Casey, 2026-10-14).
    -- Not in a battle or its result: "Traveling to System 9 2 8 point 2, 96
    -- percent of the way" ended the defeat screen's I (2026-10-15).
    -- Nor over Game Over ("Traveling to Class J Planet, 73 percent of the
    -- way" after the ship was destroyed, VM, 2026-10-16).
    local over = false
    pcall(function()
        for _, w in ipairs(FindAllOf("WBP_GameOver_C") or {}) do
            if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then over = true end
        end
    end)
    local trip = not over and not require("combat").screen_up() and require("system").travel_status()
    if trip then out[#out + 1] = trip end
    local text = table.concat(out, ". ") .. "."
    print("[VoyagerAccess] where: " .. text .. "\n")
    speech.say(text, true)
end

-- Entering and leaving a room window (Casey, 2026-10-11): the first room
-- window ever opened says once that Escape closes it (kept in a file, so
-- reloads and updates do not repeat it; the old per-screen F1 hint came
-- back after every reload). Said when popups.lua has read the window.
local HINT_FILE = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\hint-room-escape"

local function room_hint(_, cls)
    if cls ~= "WBP_RoomManagementV2_C" then return end
    local f = io.open(HINT_FILE, "r")
    if f then f:close() return end
    speech.say("Escape closes the room. F1 lists the keys.", false)
    local w = io.open(HINT_FILE, "w")
    if w then w:write("heard\n") w:close() end
end

-- Arriving in the ship view or the System Map says where you are, as I
-- does (Casey, 2026-10-11: resuming a game said nothing about where you
-- were). That covers a resumed game, a closed room or dialogue, and V.
-- Looked at when the game says something changed (its view change, a
-- window or dialogue closing), not every 300 ms: the mod's loops held the
-- game long enough to swallow keys (firefly82, 2026-10-21). Gone with the
-- loop: the 600 ms "view must hold for two polls", the 5 s wait after a
-- loading screen, the 2 s quiet after moving on the map and the second
-- reading 1 s after a ring closed (the ship's state hook says a room's new
-- state itself).
local stable_view = nil
local queued = false
-- The view the game last said it changed to (view.lua, from the navigation
-- bar's OnViewChanged), "ship", "system" or "other".
local event_view = nil

local function view_now()
    local ctx = M.context()
    -- Nothing in front, and the game has said which view it changed to:
    -- that view, even before its input is applied.
    if ctx == "none" and event_view then ctx = event_view end
    local v = (ctx == "ship" or ctx == "system") and ctx or "other"
    -- A window with its own button list is up (Exit to Main Menu's
    -- confirmation): "System map. Class M planet" broke into its BACK and
    -- ACCEPT (Casey, 2026-10-14).
    -- Only while that list's window is still on screen: the list is
    -- dropped at focus.lua's next look, which comes after a key, so after
    -- the Overview closed its CLOSE list still counted and the ship view
    -- was never said (VM, 2026-10-21).
    if require("focus").virtual_active() then
        local vw = require("focus").virtual_window()
        local w = vw and StaticFindObject(vw)
        if w and w:IsValid() and require("screen").shown(w) then v = "other" end
    end
    -- The confirmation opens before its button list exists (heard again in
    -- the VM with the check above alone). Game Over too: "System map.
    -- Nothing selected" came after "Game Over. The hull ruptured..."
    -- (Casey's machine, 2026-10-15). popups.lua knows which are open.
    -- A dilemma's result (and the other front windows) before focus reaches
    -- its button: "System map. Nothing selected" came between the result
    -- and its CLOSE (Q Trial, VM, 2026-10-21).
    for _, wp in ipairs(require("popups").open_windows()) do
        if wp:find("WBP_PauseMenu_Confirms_C", 1, true) or wp:find("WBP_GameOver_C", 1, true) or front_window(wp) then v = "other" end
    end
    return v
end

-- A view is said once it has held for VIEW_HOLD_MS and no loading screen or
-- main menu came up meanwhile: arriving in a new sector said "System map.
-- Nothing selected" twice as the view flickered away and back, and leaving
-- to the main menu said "System map" on the way out (VM, 2026-10-21; 0.3.67
-- waited 600 ms in its loop). One delayed check, not a loop.
local VIEW_HOLD_MS = 400
-- Windows whose closing never leads to a loading screen or the main menu:
-- after one of them the view is said after a short hold. Escape from a
-- room window took 530 to 700 ms to say "Ship view" (NVDA log times, VM,
-- 2026-10-21; tools\latency_report.py). The pause menu and its
-- confirmations keep the long hold (Exit to Main Menu).
local QUICK_CLOSE_MS = 120
local QUICK_CLOSE = { WBP_RoomManagementV2_C = true, WBP_OverviewInfoWidget_C = true,
    -- Not the info card (WBP_CommonInfoWidget_C): the next card can follow
    -- in the same widget a moment after one closes.
    WBP_POIMultipleChoice_C = true, WBP_LeaveSector_C = true,
    WBP_LogEventWidget_Multitab_C = true, WBP_RadialMenu_C = true, WBP_ConstructionInfoWidget_C = true,
    WBP_ResearchInfoWidget_C = true, WBP_EnergyLossInfoWidget_C = true }
local closed_class, closed_at = nil, -100
local pending_view, view_token = nil, 0
local function leaving()
    -- The game's own state first: USTVGameStateSubsystem runs a transition
    -- for every load and for the way out to the main menu (CurrentTransition,
    -- e.g. STVGameStateTransitionContinueAutoSavegame,
    -- STVGameStateTransitionToMainMenu), and CurrentState is 3 (InGame) only
    -- in play (2 is the main menu). Seen on 2026-10-22 through two loads.
    -- No event marks the end of a load (loading screen, transition and
    -- activation hooks all silent then; probe 2026-10-22), so the look
    -- below still comes back each second while loading.
    -- A battle and its setup, waited out like a loading screen: "System
    -- map. Nothing selected" came between the Combat Hero Selection
    -- tutorial and "Prepare for combat" (demo, VM, 2026-10-22). Asked
    -- before the game state, which answers "in play" during a battle.
    local okc, battle = pcall(function() return require("combat").screen_up() end)
    if okc and battle then return true end
    -- A loading screen still fading out after the game's transition ended
    -- is waited out too (Fable review, 2026-10-22: the probe showed the
    -- transition set during a load, not that it outlives the screen).
    -- A closed loading screen the game keeps is dropped from the open list
    -- by popups (IsActivated; after the demo's first-run screen it held
    -- every view announcement, VM, 2026-10-21).
    for _, wp in ipairs(require("popups").open_windows()) do
        if wp:find("WBP_Loading_Screen_C", 1, true) then return true end
    end
    local oks, busy = pcall(function()
        -- The live subsystem, not the class default (always state 0).
        local s = nil
        for _, o in ipairs(FindAllOf("STVGameStateSubsystem") or {}) do
            if o:IsValid() and not o:GetFullName():find("Default__", 1, true) then s = o end
        end
        if not s then return nil end
        local t = s.CurrentTransition
        if t and t:IsValid() then return true end
        return s.CurrentState ~= 3
    end)
    if oks and busy ~= nil then return busy end
    -- Without the subsystem: the main menu is not one of popups' windows,
    -- so it is looked for itself (Fable review, 2026-10-21).
    for _, w in ipairs(FindAllOf("WBP_MainMenu_C") or {}) do
        if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then return true end
    end
    return false
end

local say_view   -- below

-- attempt: how many times this has waited for a loading screen to go. The
-- check comes back while one is up (up to about 18 s), and starts again
-- when the view changed during the wait: with one try, a view checked
-- during the loading screen was never said after it (demo, VM, and GPT's
-- review, 2026-10-21). Going back to the view already said cancels a wait.
local function view_look(attempt)
    attempt = attempt or 0
    local v = view_now()
    if v == stable_view then
        pending_view = nil
        view_token = view_token + 1
        return
    end
    if v == pending_view then return end
    pending_view = v
    view_token = view_token + 1
    local mine = view_token
    local quick = attempt == 0 and v ~= "other" and closed_class and QUICK_CLOSE[closed_class]
        and os.clock() - closed_at < 0.5
    ExecuteInGameThreadWithDelay(quick and QUICK_CLOSE_MS or VIEW_HOLD_MS, function()
        if view_token ~= mine then return end
        pending_view = nil
        local ok, err = pcall(function()
            if view_now() ~= v then return view_look(0) end
            -- A tutorial just closed: the screen it introduced can still be
            -- on its way. The battle setup came 500 ms after the Combat Hero
            -- Selection tutorial closed, and "System map. Nothing selected"
            -- was said in between (demo, VM, 2026-10-22).
            local popups = require("popups")
            if v ~= "other" and os.clock() - (popups.tutorial_closed_at or -100) < 0.8 and attempt < 20 then
                ExecuteInGameThreadWithDelay(500, function()
                    if view_token == mine then view_look(attempt + 1) end
                end)
                return
            end
            if v ~= "other" and leaving() then
                if attempt < 20 then
                    ExecuteInGameThreadWithDelay(500, function()
                        if view_token == mine then view_look(attempt + 1) end
                    end)
                end
                return
            end
            say_view(v)
        end)
        if not ok then print("[VoyagerAccess] view look error: " .. tostring(err) .. "\n") end
    end)
end

function say_view(v)
    stable_view = v
    if v == "other" then return end
    -- Not over one of the mod's own lists: "Ship view. Deck 2, Ruined room"
    -- broke into the J room list (2026-10-14).
    if require("ship").list_open() or require("resources").list_open() or require("view").nav_open()
        or require("whatsnew").open() or require("hotkeys").open() then return end
    -- Nor over the tech tree: opened from the Science Lab, the lab window's
    -- closing asked for a view check, and "Ship view. Deck 5, Science Lab,
    -- on" came over the tree (firefly82, 2026-10-23). The tree closing says
    -- the view again (view_again).
    if require("techtree").showing() then return end
    local here
    if v == "ship" then here = require("ship").where() or "No room selected"
    else here = require("system").where() or "Nothing selected" end
    local map = require("system").sector() and "Sector map" or "System map"
    local text = (v == "ship" and "Ship view" or map) .. ". " .. here
    -- V already said the view's name (view.toggle).
    -- What is selected then follows the name, it does not cut it off: "Ship
    -- view" was interrupted at once by "Deck 10, Stellarkartographie"
    -- (firefly82, 2026-10-21).
    local view = require("view")
    local after_name = view.toggled == v and map ~= "Sector map"
    -- The navigation list's Sector map already said its name (view.nav_enter).
    if view.nav_named == map and os.clock() - (view.nav_named_at or -100) < 3 then after_name = true end
    if after_name then text = here end
    view.toggled, view.nav_named = nil, nil
    print("[VoyagerAccess] view: " .. text .. "\n")
    speech.say(text, not after_name)
end

-- Something that can change the view happened: one look on the next tick.
-- view: the view the game said it changed to, when the call comes from its
-- view change event.
function M.view_check(view)
    if view then
        event_view = view
        -- The game changed to a play view, so it is not at the main menu
        -- (state file below).
        pcall(M.mark_game)
    end
    if queued then return end
    queued = true
    ExecuteInGameThread(function()
        queued = false
        local ok, err = pcall(view_look)
        if not ok then print("[VoyagerAccess] view check error: " .. tostring(err) .. "\n") end
    end)
end

-- A full-screen view of the mod's own (the tech tree) has closed: the ship
-- view or map behind it is said even though the game's view never changed.
function M.view_again()
    stable_view = nil
    M.view_check()
end

-- For the helper's update restart (Casey, 2026-10-14): it closes the game
-- for an update only at the main menu. The mod writes "menu" when the game
-- makes its main menu and "game" when it makes the HUD or shows a loading
-- screen, instead of rewriting the file about once a second (the helper
-- clears the file when the game starts).
local STATE_FILE = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\game-state.txt"
local written_state = nil
local function write_state(state)
    if state == written_state then return end
    local f = io.open(STATE_FILE, "w")
    if f then
        f:write(state .. "\n")
        f:close()
        written_state = state
    end
end

-- "game" also on each of the game's view changes: if the HUD or the loading
-- screen were reused rather than made again, a "menu" from the main menu
-- stayed in the file during play, and the update restart could close the
-- game mid-play (review of firefly82's patch, 2026-10-21). Written only on
-- a change of state.
function M.mark_game() write_state("game") end

function M.install()
    require("keys").on("f1", M.say_help)
    require("keys").on("i", M.say_where)
    local popups = require("popups")
    popups.on_read(room_hint)
    -- A room, event or report closing can bring the ship view or the map
    -- back to the front.
    popups.on_read(function() M.view_check() end)
    -- A loading screen: looked at every second until it has gone, then the
    -- view is checked. The view after a load otherwise came only from the
    -- navigation bar's view event, and when that was not hooked the view was
    -- said at the first window after the load instead (VM, 2026-10-21).
    -- The game says when a load ends: STVJourneySubsystem's
    -- OnStateTransitionFinished comes at the end of every transition (a
    -- load, ship and map, entering and leaving an event; firefly82's probe,
    -- 2026-10-23), so the view is checked then. The look below stays as a
    -- slower, bounded fallback.
    local transition_hooked = pcall(RegisterHook, "/Script/STVoyager.STVJourneySubsystem:OnStateTransitionFinished", function()
        ExecuteInGameThread(function()
            -- With the loading screen's own state (GXCommonActivatableWidget
            -- IsActivated): firefly82 saw this event about a second before
            -- the loading screen went (25 October); this line says whether
            -- the load-end fallbacks can wait for the screen's deactivation
            -- instead (his proposal, 26 October). Logging only.
            local load = "none"
            pcall(function()
                for _, w in ipairs(FindAllOf("WBP_Loading_Screen_C") or {}) do
                    if w:IsValid() and not w:GetFullName():find("Default__", 1, true) then
                        load = tostring(w:IsActivated())
                    end
                end
            end)
            print("[VoyagerAccess] help: transition finished, loading screen activated: " .. load .. "\n")
            pcall(M.view_check)
        end)
    end)
    print("[VoyagerAccess] help: transition hook " .. (transition_hooked and "installed" or "not installed") .. "\n")
    local load_watch = 0
    popups.on_read(function(_, cls)
        if cls ~= "WBP_Loading_Screen_C" then return end
        load_watch = load_watch + 1
        local mine, tries = load_watch, 0
        local every = transition_hooked and 3000 or 1000
        local function look()
            if load_watch ~= mine then return end
            tries = tries + 1
            if not leaving() then return M.view_check() end
            if tries < 60000 / every then ExecuteInGameThreadWithDelay(every, look) end
        end
        ExecuteInGameThreadWithDelay(every, look)
    end)
    popups.on_close(function(_, cls)
        closed_class, closed_at = cls, os.clock()
        -- Closed some other way than the mod's Enter (Escape, the mouse).
        if cls == "WBP_TutorialInfoWidget_C" then popups.tutorial_closed_at = os.clock() end
        M.view_check()
        -- Once more a moment later: as the Overview closed, its button list
        -- (CLOSE) was still up, the view still counted as "other", and
        -- nothing looked again, so the ship view was never said (VM,
        -- 2026-10-21).
        if QUICK_CLOSE[cls] then
            ExecuteInGameThreadWithDelay(250, function() M.view_check() end)
        end
    end)
    popups.on_widget("WBP_MainMenu_C", function()
        write_state("menu")
        -- Back at the main menu: the view the game last changed to is over.
        event_view, stable_view = nil, nil
    end)
    popups.on_widget("WBP_HUD_C", function() write_state("game") M.view_check() end)
    popups.on_widget("WBP_Loading_Screen_C", function() write_state("game") end)
    -- As the mod starts (a reload): where the game is now.
    local menu = false
    for _, w in ipairs(FindAllOf("WBP_MainMenu_C") or {}) do
        if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then menu = true end
    end
    write_state(menu and "menu" or "game")
    M.view_check()
end

return M
