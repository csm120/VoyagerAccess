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
        .. "Enter opens the room. V switches to the System Map. I says where you are.",
    system = "Up and Down move through the points of interest. Home and End go to the nearest and the farthest. "
        .. "Enter opens Scan and Set course. Backspace closes that list. V switches to the ship.",
    room = "Up and Down move between the buttons. Enter uses one. Left and Right switch tabs. Escape closes the room.",
    event = "Up and Down move between the options. Where an option can take a hero, Left and Right choose one first. Enter picks the option. R reads the locked options.",
    mission = "Up and Down move through the choices, their heroes and Confirm. Home and End go to the first and last. "
        .. "Enter on a hero picks them for that choice, then Enter on its Confirm makes the choice. "
        .. "A hero below the skill needed can still succeed. After a result, Enter continues and R repeats it.",
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
    none = "O reads your objective. C reads resources, energy and morale. V switches between the ship and the System Map. "
        .. "I says where you are. R repeats the last line. Ctrl+F12 lists what is new in Voyager Access.",
}

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

function M.say_help()
    local ctx = require("awaymission").keys_active() and "mission" or M.context()
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

function M.say_where()
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
        elseif ctx == "dialogue" or ctx == "cutscene" or ctx == "story" then
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
                if title and title ~= "" then parts[1] = title end
            end
            parts[2] = f.current_label()
            -- The team screen said "Menu" (demo, VM, 2026-10-15).
            if parts[1] == "Menu" and parts[2] and parts[2]:find("^Away team slot") then parts[1] = "Away team" end
        end
    end
    local out = {}
    for _, p in ipairs(parts) do
        if p and p ~= "" then out[#out + 1] = (p:gsub("%.%s*$", "")) end
    end
    -- A trip under way, wherever L is pressed (Casey, 2026-10-14).
    -- Not in a battle or its result: "Traveling to System 9 2 8 point 2, 96
    -- percent of the way" ended the defeat screen's I (2026-10-15).
    local trip = not require("combat").screen_up() and require("system").travel_status()
    if trip then out[#out + 1] = trip end
    local text = table.concat(out, ". ") .. "."
    print("[VoyagerAccess] where: " .. text .. "\n")
    speech.say(text, true)
end

-- Entering and leaving a room window (Casey, 2026-10-11): the first room
-- window ever opened says once that Escape closes it (kept in a file, so
-- reloads and updates do not repeat it; the old per-screen F1 hint came
-- back after every reload).
local HINT_FILE = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\hint-room-escape"
local room_was_open = false

-- Arriving in the ship view or the System Map says where you are, as L
-- does (Casey, 2026-10-11: resuming a game said nothing about where you
-- were). That covers a resumed game, a closed room or dialogue, and V. A
-- view must hold for two polls (600 ms) before it is spoken, so loading
-- screens do not make it speak twice.
local stable_view, candidate, candidate_polls = nil, nil, 0

-- After a loading screen, wait before saying where you are: a new campaign's
-- narration starts about 3 s after the load, and "System map. Nothing
-- selected" was said first (2026-10-14).
local LOAD_SETTLE = 5
local last_loading = -100

local function view_poll()
    for _, w in ipairs(FindAllOf("WBP_Loading_Screen_C") or {}) do
        if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then
            last_loading = os.clock()
        end
    end
    if os.clock() - last_loading < LOAD_SETTLE then
        candidate, candidate_polls = nil, 0
        return
    end
    local ctx = M.context()
    local v = (ctx == "ship" or ctx == "system") and ctx or "other"
    -- A window with its own button list is up (Exit to Main Menu's
    -- confirmation): "System map. Class M planet" broke into its BACK and
    -- ACCEPT (Casey, 2026-10-14).
    if require("focus").virtual_active() then v = "other" end
    -- The confirmation opens before its button list exists (heard again in
    -- the VM with the check above alone).
    -- Game Over too: "System map. Nothing selected" came after "Game Over.
    -- The hull ruptured..." (Casey's machine, 2026-10-15).
    for _, cls in ipairs({ "WBP_PauseMenu_Confirms_C", "WBP_PauseMenu_C", "WBP_GameOver_C" }) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then
                v = "other"
            end
        end
    end
    if v ~= candidate then
        candidate, candidate_polls = v, 1
        return
    end
    candidate_polls = candidate_polls + 1
    if candidate_polls < 2 or v == stable_view then return end
    stable_view = v
    if v == "other" then return end
    -- Not over one of the mod's own lists: "Ship view. Deck 2, Ruined room"
    -- broke into the J room list (2026-10-14).
    if require("ship").list_open() or require("resources").list_open() or require("view").nav_open()
        or require("whatsnew").open() or require("hotkeys").open() then return end
    -- Not while moving through the map: a tutorial closing made "System
    -- map. Repair station, 3 of 12" repeat the point just heard (2026-10-14).
    if v == "system" and os.clock() - (require("system").last_move or -100) < 2 then return end
    local here
    if v == "ship" then here = require("ship").where() or "No room selected"
    else here = require("system").where() or "Nothing selected" end
    local map = require("system").sector() and "Sector map" or "System map"
    local text = (v == "ship" and "Ship view" or map) .. ". " .. here
    print("[VoyagerAccess] view: " .. text .. "\n")
    speech.say(text, true)
end

-- For the helper's update restart (Casey, 2026-10-14): it closes the game
-- for an update only at the main menu, so the mod reports "menu" or "game"
-- about once a second. The helper treats a file older than a few seconds
-- as not at the menu.
local STATE_FILE = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\game-state.txt"
local state_ticks = 0

local function write_state()
    state_ticks = state_ticks + 1
    if state_ticks < 3 then return end
    state_ticks = 0
    local menu = false
    for _, w in ipairs(FindAllOf("WBP_MainMenu_C") or {}) do
        if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then
            menu = true
        end
    end
    local f = io.open(STATE_FILE, "w")
    if f then
        f:write(menu and "menu\n" or "game\n")
        f:close()
    end
end

local function room_poll()
    pcall(write_state)
    local open = require("rooms").window_open()
    if open and not room_was_open then
        local f = io.open(HINT_FILE, "r")
        if f then
            f:close()
        else
            speech.say("Escape closes the room. F1 lists the keys.", false)
            local w = io.open(HINT_FILE, "w")
            if w then w:write("heard\n") w:close() end
        end
    end
    room_was_open = open
    view_poll()
end

function M.install()
    require("keys").on("f1", M.say_help)
    require("keys").on("i", M.say_where)
    LoopInGameThreadWithDelay(300, function()
        local ok, err = pcall(room_poll)
        if not ok then print("[VoyagerAccess] room poll error: " .. tostring(err) .. "\n") end
    end)
end

return M
