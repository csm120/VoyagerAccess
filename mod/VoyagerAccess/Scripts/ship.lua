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
            list[#list + 1] = { hull = h, deck = deck, y = loc.Y }
        end
    end
    -- Top deck first; on a deck, screen left (high Y) first.
    table.sort(list, function(a, b)
        if a.deck ~= b.deck then return a.deck < b.deck end
        return a.y > b.y
    end)
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
        if cy:lower() == "ready" then
            -- A cleared ruin read "Empty building space, removing done".
            if raw == "None" and st:lower():find("^remov") then return "just cleared" end
            return st:lower() .. " done"
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

local function describe(r, with_deck)
    local t = r.hull:GetRoomType()
    local text = room_name(t)
    local state = room_state(r.hull, raw_name(t))
    if raw_name(t) == "None" and state == "" and not deck_has_life(r.deck) then state = "no life support" end
    if state ~= "" then text = text .. ", " .. state end
    if with_deck then text = "Deck " .. r.deck .. ", " .. text end
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

-- At either end of a deck Left and Right repeat the room, with no extra
-- words (Casey, 2026-10-10). prefix is optional text said first.
local function select(r, with_deck, prefix)
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
        if raw ~= "RuinedRoom" and raw ~= "TurboShaft" then
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

return M
