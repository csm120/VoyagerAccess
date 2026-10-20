-- The ship view (side view of Voyager's decks): arrow keys walk the rooms,
-- Enter opens the selected one. The game only offers the mouse and the
-- gamepad here (IMC_ShipManagement, the game's own key bindings).
--
-- Each room slot is an STVRoomHull actor in the level (95 in the first
-- sector). Its height gives the deck: decks are 400 units apart, and the
-- top one (the Bridge's) is Deck 1. Its sideways position orders rooms on
-- a deck; the quest's "lower left" Stellar Cartography has a high Y, so
-- screen left is high Y (inferred from one room; check with Casey).
-- The hull's widget (WBP_Button_RoomSelection) shows the state: Damaged,
-- Offline, Removing, and cycles left.

local speech = require("speech")
local screen = require("screen")
local crumb = require("crumb")

local M = {}

local TOP_DECK_Z = 1003300
local DECK_HEIGHT = 400

-- Internal names that differ from what the game shows. Fill in from the
-- room windows as they are seen.
local NAMES = {
    RuinedRoom = "Ruined room",
    -- A cleared room: read "None, on" (2026-10-14).
    None = "Empty building space",
    -- The game calls it Emergency Quarters (2026-10-14).
    EnlistedQuarter = "Emergency quarters",
    TurboShaft = "Turbolift",
    TacticalScannerAndSensorArray = "Tactical scanner and sensor array",
    -- The build ring's centre says Engineering Office (2026-10-16).
    EngineeringOffices = "Engineering office",
    -- Names the game shows (build ring, tech tree, VM, 2026-10-15 and 16).
    OfficersQuarter = "Officers' quarters",
    PhaserArray = "Phaser control room",
    DisruptorArray = "Disruptor control room",
    -- The quest's "Stellar Cartography": powering this room completed it.
    AstrometricsLaboratory = "Stellar cartography",
}

local ROOM_TYPE = nil
local function raw_name(t)
    ROOM_TYPE = ROOM_TYPE or StaticFindObject("/Script/STVoyager.ESTVRoomType")
    return (ROOM_TYPE:GetNameByValue(t):ToString():gsub("^ESTVRoomType::", ""))
end

-- The game's own name for a room type, in the game's language
-- (STVConstructionUtils RoomTypeToText; outside review, 2026-10-17): the
-- names made from the internal ones differed from what the game shows
-- ("Main deflector" for Navigational Deflector, "Bio lab" for Bio
-- Laboratory) and were English only. Kept per type.
local KEEP = { None = true, TurboShaft = true }
local game_names = {}
local function game_name(t)
    if game_names[t] ~= nil then return game_names[t] or nil end
    local ok, s = pcall(function()
        return StaticFindObject("/Script/STVoyager.Default__STVConstructionUtils")
            :RoomTypeToText(FindFirstOf("STVConstructionManager"), t):ToString()
    end)
    if ok and s and s ~= "" then game_names[t] = s; return s end
    return nil
end

local function room_name(t)
    local raw = raw_name(t)
    if KEEP[raw] then return NAMES[raw] end
    local g = game_name(t)
    if g then return g end
    if NAMES[raw] then return NAMES[raw] end
    raw = raw:gsub("^Tutorial_", "")
    -- AstrometricsLaboratory -> Astrometrics laboratory
    local words = raw:gsub("(%l)(%u)", "%1 %2"):lower()
    return (words:gsub("^%l", string.upper))
end

local selected = nil   -- { deck = n, y = number } of the selected room

-- The selection is kept in a file: a mod reload (an update, or development)
-- wiped it, and leaving a room then started over at Deck 1 (2026-10-11).
local SELECTED_FILE = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\ship-selected.txt"

local function save_selected()
    local f = io.open(SELECTED_FILE, "w")
    if f then
        f:write(string.format("%d %f\n", selected.deck, selected.y))
        f:close()
    end
end

do
    local f = io.open(SELECTED_FILE, "r")
    if f then
        local deck, y = (f:read("l") or ""):match("^(%d+) (%S+)$")
        f:close()
        if deck and tonumber(y) then selected = { deck = tonumber(deck), y = tonumber(y) } end
    end
end

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

-- All room hulls as { hull, deck, y }, looked up fresh (never kept).
local function rooms()
    local list = {}
    for _, h in ipairs(FindAllOf("STVRoomHull") or {}) do
        if h:IsValid() and path_of(h):find("PersistentLevel", 1, true) then
            local loc = h:K2_GetActorLocation()
            local deck = math.floor((TOP_DECK_Z - loc.Z) / DECK_HEIGHT + 0.5) + 1
            list[#list + 1] = { hull = h, deck = deck, low = deck, y = loc.Y }
            -- A room more than one deck tall is on each deck it covers
            -- (deck is its lowest): the Holodeck on decks 4 to 6 was only
            -- reached on deck 6, though a sighted player sees it on all
            -- three (firefly82's review, 2026-10-19). The upper decks get
            -- the same room again, marked so the J list shows it once.
            local tall = 1
            pcall(function() tall = math.max(math.floor(h.GridSize.Z + 0.5), 1) end)
            for k = 1, tall - 1 do
                list[#list + 1] = { hull = h, deck = deck - k, low = deck, y = loc.Y, upper = true }
            end
        end
    end
    -- Top deck first; on a deck, screen left (high Y) first.
    table.sort(list, function(a, b)
        if a.deck ~= b.deck then return a.deck < b.deck end
        return a.y > b.y
    end)
    -- Decks are counted from the ship's own top deck. TOP_DECK_Z is
    -- Voyager's, so the Equinox (8 decks, Q Trials) read Decks 5 to 12,
    -- with its Bridge on "Deck 5" (Equinox DLC, VM, 2026-10-19). Voyager's
    -- top deck is already 1, so nothing changes there.
    local top = list[1] and list[1].deck or 1
    if top > 1 then
        for _, r in ipairs(list) do r.deck = r.deck - top + 1; r.low = r.low - top + 1 end
    end
    return list
end

-- The label widget has one part per state and shows the one that applies.
-- Read 2026-10-10: Stellar Cartography showed "Offline" before its power
-- was switched on and no state part after; the Bridge and Main Engineering
-- show none. So a working room with no state part is "Online".
local STATE_PARTS = {
    { "Damaged_NoLifeSupport_State", "Damaged, no life support" },
    { "Damaged_State", "Damaged" },
    { "Offline_State", "off" },
    { "PauseImage", "Paused" },
}
-- Ruined rooms and turbolifts are not rooms you power. Life support is:
-- each deck has one, and it shows Offline_State when switched off (read
-- 2026-10-11). "on" and "off" match the power button (Casey, 2026-10-11).
local NO_POWER = { RuinedRoom = true, TurboShaft = true, None = true }

local function room_state(h, raw)
    local w = h.RoomHullWidget
    if not (w and w:IsValid()) then return "" end
    -- Work in progress ("Repairing, 3 cycles", "Building", "Removing"): a
    -- room under repair was read "on" (2026-10-14). IsVisible is true on
    -- every room's template text; only screen.shown tells the real ones.
    local ok, busy = pcall(function()
        -- Up to the hull widget only: a Bio Lab just started was read "on"
        -- because its whole hull widget was Hidden, with "Building, 10
        -- cycles" correct inside it (VM, 2026-10-17).
        if not require("screen").shown(w.StateText, w) then return nil end
        local st = w.StateText:GetText():ToString()
        local cy = w.CycleText:GetText():ToString()
        if st == "" then return nil end
        -- Finished work waits for the Construction Report's Close: the cycle
        -- text says "Ready", read "Cargo bay, building, ready" (VM,
        -- 2026-10-16).
        -- Decided from the room button's own State (ESTVRoomState: 1
        -- Building, 2 Upgrading, 3 Repairing, 5 Removing) and its
        -- RemainingCycles, read in the VM: the English "ready" missed it in
        -- every other language, and the work-team rule below then added a
        -- wrong "paused" (firefly82's review, 2026-10-19). The word stays as
        -- a fallback.
        local kind, left = nil, nil
        pcall(function() kind, left = w.State.State, w.State.RemainingCycles end)
        local working = kind == 1 or kind == 2 or kind == 3 or kind == 5
        if (working and left == 0) or cy:lower() == "ready" then
            -- A cleared ruin read "Empty building space, removing done".
            if raw == "None" and (kind == 5 or st:lower():find("^remov")) then return "just cleared" end
            -- Enter on the room finishes it (VM, 2026-10-19); the screen
            -- shows "Ready", which says as much to a sighted player.
            return st:lower() .. " done" .. require("hints").text("done_enter", ", Enter finishes it")
        end
        -- Paused work keeps its text ("removing, 3 cycles") but has no
        -- work team (VM, 2026-10-16: 0 teams paused, 1 after Resume).
        local paused = false
        pcall(function()
            local d = FindFirstOf("STVConstructionManager"):BP_GetRoomDataBySlot(h:BP_GetSlotIndex())
            paused = #d.AssignedWorkTeams == 0
        end)
        return st:lower() .. (paused and ", paused" or "") .. (cy ~= "" and (", " .. cy:lower()) or "")
    end)
    if ok and busy then return busy end
    for _, part in ipairs(STATE_PARTS) do
        local x = w[part[1]]
        if x and x:IsValid() and x:IsVisible() then return part[2] end
    end
    return NO_POWER[raw] and "" or "on"
end

-- Whether a deck's life support is running. A building space on a deck
-- without it is inaccessible (the game's own Life Support description), and
-- Enter on one opened nothing and said nothing (deck 3, life support
-- damaged, VM, 2026-10-18).
local function deck_has_life(deck)
    for _, r in ipairs(rooms()) do
        if r.deck == deck and raw_name(r.hull:GetRoomType()) == "LifeSupport" then
            return room_state(r.hull, "LifeSupport") == "on"
        end
    end
    return true   -- a deck with no life support room of its own (not seen)
end

-- How many decks a room spans (its hull's GridSize.Z: Holodeck 3, Main
-- Engineering 2). r.deck is its lowest deck. The Holodeck on decks 4 to 6
-- read "Deck 6, Holodeck, Damaged, no life support" while decks 5 and 6
-- had life support; deck 4's was damaged, and a sighted player sees the
-- tall room and the dark deck (VM, 2026-10-18).
local function decks_tall(r)
    local z = 1
    pcall(function() z = math.floor(r.hull.GridSize.Z + 0.5) end)
    return math.max(z, 1)
end

local function describe(r, with_deck)
    local t = r.hull:GetRoomType()
    local text = room_name(t)
    local state = room_state(r.hull, raw_name(t))
    local low = r.low or r.deck
    if raw_name(t) == "None" and state == "" and not deck_has_life(low) then state = "no life support" end
    local tall = decks_tall(r)
    if tall > 1 and state:find("no life support", 1, true) then
        local dark = {}
        for d = low - tall + 1, low do
            if not deck_has_life(d) then dark[#dark + 1] = tostring(d) end
        end
        if #dark > 0 then
            state = state:gsub("no life support", "no life support on deck " .. table.concat(dark, " and "), 1)
        end
    end
    if state ~= "" then text = text .. ", " .. state end
    if with_deck then
        -- A tall room says the deck the player is on first: moving down a
        -- turbo lift said "Decks 2 to 9, Turbo lift" four times over decks
        -- 6 to 9, which sounded stuck (firefly82's review, 2026-10-20).
        if tall > 1 then
            text = "Deck " .. r.deck .. ", " .. text .. ", decks " .. (low - tall + 1) .. " to " .. low
        else
            text = "Deck " .. low .. ", " .. text
        end
    end
    return text
end

-- True while the ship view's own input is applied and nothing sits on top.
local SHIP_CONTEXT = nil
function M.active()
    local sub = nil
    for _, s in ipairs(FindAllOf("EnhancedInputLocalPlayerSubsystem") or {}) do
        if s:IsValid() and path_of(s):find("^/Engine/Transient%.") then sub = s end
    end
    if not sub then return false end
    if not (SHIP_CONTEXT and SHIP_CONTEXT:IsValid()) then
        SHIP_CONTEXT = nil
        for _, ctx in ipairs(FindAllOf("InputMappingContext") or {}) do
            if ctx:GetFName():ToString() == "IMC_ShipManagement" then SHIP_CONTEXT = ctx end
        end
    end
    return SHIP_CONTEXT ~= nil and sub:HasMappingContext(SHIP_CONTEXT, {})
end

-- How far a room reaches either side of its centre. A room's position is
-- its centre, so a Bio Lab built on the space you chose was as near as the
-- empty space beside it, and "Empty building space" was read after building
-- (VM, 2026-10-17). Cells are the grid's DefaultRoomExtend.Y (400) wide.
local half_cache = {}
local function half_span(t)
    if half_cache[t] then return half_cache[t] end
    if NO_POWER[raw_name(t)] then half_cache[t] = 0; return 0 end
    local ok, half = pcall(function()
        local cell = FindFirstOf("STVRoomGrid").DefaultRoomExtend.Y
        local w = require("construction").extent(t)
        return (w - 1) * cell / 2
    end)
    if not (ok and half and half >= 0) then return 0 end
    half_cache[t] = half
    return half
end

local function index_of_selected(list)
    if not selected then return nil end
    local best, best_d = nil, math.huge
    for i, r in ipairs(list) do
        if r.deck == selected.deck then
            local d = math.max(0, math.abs(r.y - selected.y) - half_span(r.hull:GetRoomType()))
            if d < best_d then best, best_d = i, d end
        end
    end
    return best
end

-- The game's own room keys (E power or repair, F upgrade, T demolish) act
-- on the room under the mouse pointer, picked again on every key press:
-- with the Science Laboratory announced, E switched off the Mess Hall under
-- the resting pointer (firefly82's review, 2026-10-19; reproduced in the VM
-- the same day, E left the announced lab on). So the pointer goes onto the
-- room the arrows reach, the way a sighted player points at it. Pointing
-- only: nothing is clicked.
-- A room off screen cannot be pointed at (the Workshop on deck 11 with the
-- camera on deck 5: E then switched off the lab under the old pointer,
-- VM, 2026-10-19), so the camera goes to it first with the game's own
-- ForceCameraOnRoom(slot), which centred the room and stayed in the ship
-- view, and the pointer follows once the camera is there.
local function point_at(hull, tries)
    tries = tries or 0
    pcall(function()
        local pc = FindFirstOf("PlayerController")
        local size = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportSize(pc)
        local w, h = size.X, size.Y
        local st = {}
        pc:ProjectWorldLocationToScreen(hull:K2_GetActorLocation(), st, false)
        if not (w and h and h > 0 and st.X and st.Y) then return end
        if st.X < 0 or st.Y < 0 or st.X > w or st.Y > h then
            print(string.format("[VoyagerAccess] ship: room off screen at %.0f,%.0f\n", st.X, st.Y))
            if tries > 0 then return end
            local slot = hull:BP_GetSlotIndex()
            FindFirstOf("STVConstructionPawn"):ForceCameraOnRoom(slot)
            ExecuteInGameThreadWithDelay(600, function()
                pcall(function()
                    for _, r in ipairs(rooms()) do
                        if r.hull:BP_GetSlotIndex() == slot then point_at(r.hull, 1) end
                    end
                end)
            end)
            return
        end
        local r = 350 / 1080 * h   -- the helper's ring radius
        speech.ring_mouse((st.X - w / 2) / r, (st.Y - h / 2) / r)
    end)
end

-- At either end of a deck Left and Right repeat the room, with no extra
-- words (Casey, 2026-10-10). prefix is optional text said first.
local function select(r, with_deck, prefix)
    point_at(r.hull)
    selected = { deck = r.deck, y = r.y }
    save_selected()
    local text = describe(r, with_deck)
    -- Decks of identical "Ruined room"s gave no sign of moving or of the
    -- deck's end (2026-10-14), so say the room's place on its deck.
    local n, count, best = 0, 0, math.huge
    for _, o in ipairs(rooms()) do
        if o.deck == r.deck then
            count = count + 1
            local d = math.abs(o.y - r.y)
            if d < best then n, best = count, d end
        end
    end
    if count > 1 and n > 0 then text = string.format("%s, %d of %d", text, n, count) end
    if prefix then text = prefix .. ": " .. text end
    print("[VoyagerAccess] ship: " .. text .. "\n")
    speech.say(text, true)
end

-- The ship view is a grid, so it uses all four arrows (Casey, 2026-10-11:
-- Page Up and Page Down are hard to find on laptops). Left and Right: the
-- next room on this deck.
function M.step(dir)
    crumb.at("ship: step")
    local list = rooms()
    if #list == 0 then return end
    local i = index_of_selected(list)
    if not i then return select(list[1], true) end
    local r = list[i + dir]
    if not (r and r.deck == list[i].deck) then
        return select(list[i], false)
    end
    select(r, false)
end

-- Home and End: the first and last room on this deck.
function M.edge(last)
    local list = rooms()
    if #list == 0 then return end
    local i = index_of_selected(list)
    if not i then return select(list[1], true) end
    local deck = list[i].deck
    local pick = nil
    for _, r in ipairs(list) do
        if r.deck == deck and (last or not pick) then pick = r end
    end
    select(pick, false)
end

-- Up and Down (or Page Up and Page Down): the nearest room on the next deck
-- that has rooms.
function M.deck(dir)
    crumb.at("ship: deck")
    local list = rooms()
    if #list == 0 then return end
    local i = index_of_selected(list)
    if not i then return select(list[1], true) end
    local here = list[i]
    local target, best_d = nil, math.huge
    local want = nil
    for _, r in ipairs(list) do
        if (dir > 0 and r.deck > here.deck) or (dir < 0 and r.deck < here.deck) then
            if not want or (dir > 0 and r.deck < want) or (dir < 0 and r.deck > want) then want = r.deck end
        end
    end
    if not want then
        return select(here, true)
    end
    for _, r in ipairs(list) do
        if r.deck == want and math.abs(r.y - here.y) < best_d then target, best_d = r, math.abs(r.y - here.y) end
    end
    select(target, true)
end

-- J: the ship's rooms as a list (Casey, 2026-10-14: what a sighted player
-- sees at a glance gets a key). Ruined rooms and turbolifts are left out,
-- since a deck of "Ruined room"s hid Stellar Cartography. Up and Down move,
-- Home and End go to the ends, Enter selects the room in the ship view
-- (Enter again opens it), Backspace or J closes.
local jump = nil   -- { items = { {deck, y, text} }, index }

function M.list_open() return jump ~= nil end

local function say_jump()
    local it = jump.items[jump.index]
    speech.say(string.format("%s, %d of %d", it.text, jump.index, #jump.items), true)
end

function M.list_toggle()
    if jump then
        jump = nil
        speech.say("Closed", true)
        return
    end
    local items = {}
    for _, r in ipairs(rooms()) do
        local raw = raw_name(r.hull:GetRoomType())
        -- Empty building space is listed: it is where rooms are built.
        if raw ~= "RuinedRoom" and raw ~= "TurboShaft" and not r.upper then
            items[#items + 1] = { deck = r.deck, y = r.y, text = describe(r, true) }
        end
    end
    if #items == 0 then
        speech.say("No rooms", true)
        return
    end
    local index = 1
    if selected then
        for i, it in ipairs(items) do
            if it.deck == selected.deck and math.abs(it.y - selected.y) < 1 then index = i end
        end
    end
    jump = { items = items, index = index }
    require("focus").park_focus()
    say_jump()
end

function M.list_step(dir)
    if jump.items[jump.index + dir] then jump.index = jump.index + dir end
    say_jump()
end

function M.list_edge(last)
    jump.index = last and #jump.items or 1
    say_jump()
end

function M.list_close()
    if not jump then return false end
    jump = nil
    speech.say("Closed", true)
    return true
end

function M.list_enter()
    local it = jump.items[jump.index]
    jump = nil
    for _, r in ipairs(rooms()) do
        if r.deck == it.deck and math.abs(r.y - it.y) < 1 then return select(r, true) end
    end
end

-- The selected room's hull actor, or nil (construction.lua builds there).
function M.selected_hull()
    local list = rooms()
    local i = index_of_selected(list)
    return i and list[i].hull or nil
end

-- For L (where am I): the selected room with its deck, or nil.
function M.where()
    local list = rooms()
    local i = index_of_selected(list)
    return i and describe(list[i], true) or nil
end

-- The state of the first room of a raw type ("MainDeflector"): "Damaged",
-- "off", "on" and so on, or nil when the ship has none. For the hull line
-- in C (resources.lua).
function M.state_of(raw)
    for _, r in ipairs(rooms()) do
        local t = r.hull:GetRoomType()
        if raw_name(t) == raw then return room_state(r.hull, raw) end
    end
    return nil
end

-- I pressed twice: the selected room's details, as the game's info panel
-- shows them when the pointer rests on the room (level, energy, crew, what
-- E does there and what it costs), opened as a list (Casey, 2026-10-19).
-- The pointer is put on the room first, so the panel is this room's.
function M.details()
    local list = rooms()
    local i = index_of_selected(list)
    if not i then
        speech.say("No room selected. Use the arrow keys to choose one.", true)
        return
    end
    local slot, title = list[i].hull:BP_GetSlotIndex(), describe(list[i], true)
    point_at(list[i].hull)
    -- A room off screen waits for the camera first (point_at moves the
    -- pointer 600 ms later): the Shuttle bay gave "No details" at 400 ms.
    local function try(n)
        ExecuteInGameThreadWithDelay(400, function()
            pcall(function()
                local tip = require("tooltip")
                local panel = tip.room_panel()
                if not panel then
                    if n < 5 then return try(n + 1) end
                    speech.say("No details shown for this room", true)
                    return
                end
                require("resources").show_details(title, tip.lines(panel))
            end)
        end)
    end
    try(1)
end

-- The selected room's own state word ("on", "off", "Damaged"), for its
-- power button: deciding from the button's English label ("Switch Off")
-- failed in every other language (firefly82's review, 2026-10-19).
function M.selected_state()
    local list = rooms()
    local i = index_of_selected(list)
    if not i then return nil end
    return room_state(list[i].hull, raw_name(list[i].hull:GetRoomType()))
end

-- Enter: what a mouse click on the room does.
function M.open()
    crumb.at("ship: open")
    local list = rooms()
    local i = index_of_selected(list)
    if not i then
        speech.say("No room selected. Use the arrow keys to choose one.", true)
        return
    end
    print("[VoyagerAccess] ship: open " .. describe(list[i], true) .. "\n")
    if raw_name(list[i].hull:GetRoomType()) == "None" and not deck_has_life(list[i].deck) then
        speech.say("Not possible: deck " .. list[i].deck .. " has no life support running, so its building space is closed. Repair or switch on its Life Support first.", true)
        return
    end
    -- ClickedRoom opens the HOVERED room, not this hull's: with the mouse
    -- resting over Life Support it opened Life Support (2026-10-11; also
    -- why the Aeroshuttle bay opened Stellar Cartography). Hover it first.
    list[i].hull:OnHoveredRoom()
    list[i].hull:ClickedRoom()
    -- Work finished while the Construction Report was left with Enter Ship
    -- waits as "repairing done"; clicking the room finishes it, with nothing
    -- opening (Workshop, Q Trial, VM, 2026-10-19). Say the new state.
    if describe(list[i], false):find(" done", 1, true) then
        local deck, y = list[i].deck, list[i].y
        ExecuteInGameThreadWithDelay(800, function()
            pcall(function()
                for _, r in ipairs(rooms()) do
                    if r.deck == deck and math.abs(r.y - y) < 1 then speech.say(describe(r, false), true) end
                end
            end)
        end)
    end
end

-- Development (tools\vm\vm-room.ps1): select the first room whose reading
-- matches a Lua pattern, as the room list's Enter does. Walking decks with
-- the arrows to reach one took minutes (2026-10-16).
function M.select_matching(pattern)
    for _, r in ipairs(rooms()) do
        if describe(r, true):lower():find(pattern:lower()) then
            select(r, true)
            return describe(r, true)
        end
    end
    return nil
end

-- A room type's spoken name (the build ring's reading without the mouse).
M.type_name = room_name

-- Development: every room as the mod would speak it.
function M.preview()
    local out = {}
    for _, r in ipairs(rooms()) do out[#out + 1] = describe(r, true) end
    return table.concat(out, " | ")
end

-- A room's new state, whatever changed it (the game's E key, the room
-- window, damage, a finished job): a sighted player sees "Offline" appear
-- on the room, and after E the mod said nothing, so a wrong E went
-- unnoticed (firefly82's review, 2026-10-19; E on the lab was silent in the
-- VM the same day). The game's own event, hooked on its condition listener
-- (firefly82 found it); there are several listeners, so one change arrives
-- several times and only the first per room and state is said. Said only
-- in the ship view, after the game has applied the change.
local HOOK = "/Script/STVoyager.STVConditionListener:OnBuildingChangedState"
local last_change = {}   -- slot -> { state, at }

-- UE4SS unregisters a mod's hooks itself when the mod is reloaded
-- ("Unregistering hook by id ... for mod VoyagerAccess" in UE4SS.log).
function M.install()
    local ok = pcall(RegisterHook, HOOK, function(_, payload)
        pcall(function()
            local p = payload:get()
            local slot, state = p:GetSlotID(), p:GetCurrentRoomState()
            local seen = last_change[slot]
            if seen and seen.state == state and os.clock() - seen.at < 2 then return end
            last_change[slot] = { state = state, at = os.clock() }
            ExecuteInGameThreadWithDelay(300, function()
                pcall(function()
                    if not M.active() then return end
                    for _, r in ipairs(rooms()) do
                        if r.hull:BP_GetSlotIndex() == slot then
                            local text = describe(r, false)
                            print("[VoyagerAccess] ship: changed: " .. text .. "\n")
                            speech.say(text, false)
                            return
                        end
                    end
                end)
            end)
        end)
    end)
    print("[VoyagerAccess] ship: state hook " .. (ok and "installed" or "not installed") .. "\n")
end

return M
