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
            return require("tr").fill("{s} done", require("tr").lower(st)) .. require("hints").text("done_enter", ", Enter finishes it")
        end
        -- Paused work keeps its text ("removing, 3 cycles") but has no
        -- work team (VM, 2026-10-16: 0 teams paused, 1 after Resume).
        -- The room button's own IsPaused flag, which the game sets with
        -- OnSetState (firefly82's review, 2026-10-20: the mod's work-team
        -- count rebuilt the game's rule); the count is the fallback.
        local paused = nil
        pcall(function() if type(w.IsPaused) == "boolean" then paused = w.IsPaused end end)
        if paused == nil then
            paused = false
            pcall(function()
                local d = FindFirstOf("STVConstructionManager"):BP_GetRoomDataBySlot(h:BP_GetSlotIndex())
                paused = #d.AssignedWorkTeams == 0
            end)
        end
        return require("tr").lower(st) .. (paused and ", paused" or "") .. (cy ~= "" and (", " .. require("tr").lower(cy)) or "")
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
-- Asked of the game for a slot on that deck (IsLifeSupportActiveForSlot,
-- which construction.lua uses too) rather than rebuilt from the Life
-- Support room's state (firefly82's review, 2026-10-20); the room's state
-- is the fallback.
local function deck_has_life(deck)
    local ok, ans = pcall(function()
        local cm = FindFirstOf("STVConstructionManager")
        for _, r in ipairs(rooms()) do
            if r.deck == deck and not r.upper then return cm:IsLifeSupportActiveForSlot(r.hull:BP_GetSlotIndex()) end
        end
        return nil
    end)
    if ok and type(ans) == "boolean" then return ans end
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

-- A prompt marker the game shows on a room, or on the navigation bar's
-- Ship button for all of them (WBP_RoomPrompt: an icon and CounterDisplay;
-- FSTVRoomPromptData.Counter). The Bridge showed a side mission icon with
-- "10" and the mod said only "Deck 1, Bridge, on" (room prompt probe,
-- 2026-10-21). Said as the screen shows it: the icon's kind and the
-- number, which the game does not label. An icon not known yet is logged,
-- not guessed.
local IMG_CLASS, PANEL_CLASS = nil, nil
local function prompt_icon(p)
    IMG_CLASS = IMG_CLASS or StaticFindObject("/Script/UMG.Image")
    PANEL_CLASS = PANEL_CLASS or StaticFindObject("/Script/UMG.PanelWidget")
    local found = nil
    local function walk(x, d)
        if found or d > 10 or not (x and x:IsValid() and x:IsVisible()) then return end
        if x:IsA(IMG_CLASS) then
            local ok, r = pcall(function()
                local ro = x.Brush.ResourceObject
                return ro and ro:IsValid() and ro:GetFName():ToString() or nil
            end)
            if ok and r and (r:find("Mission", 1, true) or not r:find("Gradient", 1, true)) then found = r end
        elseif x:IsA(PANEL_CLASS) then
            for i = 0, x:GetChildrenCount() - 1 do walk(x:GetChildAt(i), d + 1) end
        end
    end
    pcall(function() walk(p.WidgetTree.RootWidget, 0) end)
    return found
end

function M.prompt_words(p, stop)
    if not (p and p:IsValid() and require("screen").shown(p, stop)) then return nil end
    local icon = prompt_icon(p)
    local kind = icon and (icon:find("MainMission", 1, true) and "main mission"
        or icon:find("SideMission", 1, true) and "side mission") or nil
    if not kind then
        print("[VoyagerAccess] ship: prompt marker with icon " .. tostring(icon) .. ", not said\n")
        return nil
    end
    local n = ""
    pcall(function()
        local c = p.CounterDisplay
        if c and c:IsValid() and c:IsVisible() then n = c:GetText():ToString() end
    end)
    return kind .. (n:match("^%d+$") and (" " .. n) or "")
end

-- The markers on one room's button (its PromptVisArray), shown ones only.
local function room_prompts(h)
    local out = {}
    pcall(function()
        local w = h.RoomHullWidget
        local arr = w.PromptVisArray
        for i = 1, #arr do
            local s = M.prompt_words(arr[i], w)
            if s then out[#out + 1] = s end
        end
    end)
    return out
end

local function describe(r, with_deck)
    local t = r.hull:GetRoomType()
    local text = room_name(t)
    local state = room_state(r.hull, raw_name(t))
    local low = r.low or r.deck
    if raw_name(t) == "None" and state == "" and not deck_has_life(low) then state = "no life support" end
    -- A switched-off room on a deck whose life support is down: its tile says
    -- Offline, but the game's info panel says No life support and offers no
    -- action (the room state's bLifeSupportEnabled). "off" alone invited E,
    -- which does nothing there (Profile 01, deck 3 Phaser Control Room, VM,
    -- 2026-10-22). The demo's room button has no State struct; the deck's
    -- life support answers there.
    local dark = false
    if state == "off" and raw_name(t) ~= "LifeSupport" then
        local ok, life = pcall(function() return r.hull.RoomHullWidget.State.bLifeSupportEnabled end)
        if ok and type(life) == "boolean" then dark = not life else dark = not deck_has_life(low) end
        if dark then state = "off, no life support" end
    end
    local tall = decks_tall(r)
    if tall > 1 and state:find("no life support", 1, true) then
        local dark = {}
        for d = low - tall + 1, low do
            if not deck_has_life(d) then dark[#dark + 1] = tostring(d) end
        end
        -- Three decks read "on deck 4 and 5 and 6" (VM, 2026-10-20): a list
        -- reads "on decks 4, 5 and 6".
        -- Translated here (tr.fill): as a line-pass template its {s} took
        -- the rest of the line, ", decks 4 to 6" included, and that stayed
        -- English (German table under lupa, 2026-10-20).
        local tr = require("tr")
        local said = nil
        if #dark == 1 then
            said = tr.fill("no life support on deck {s}", dark[1])
        elseif #dark > 1 then
            local list = table.concat(dark, ", ", 1, #dark - 1) .. tr.word(" and ") .. dark[#dark]
            said = tr.fill("no life support on decks {s}", list)
        end
        if said then state = state:gsub("no life support", (said:gsub("%%", "%%%%")), 1) end
    end
    -- A lone state word in the game's language (tr.lua); longer states are
    -- phrases the line pass translates.
    -- tr.word: on | off
    if dark then
        -- "off" is a lone word (tr.word); the rest is a phrase the line pass
        -- translates.
        text = text .. ", " .. require("tr").word("off") .. state:sub(4)
    elseif state ~= "" then text = text .. ", " .. require("tr").word(state) end
    for _, s in ipairs(room_prompts(r.hull)) do text = text .. ", " .. s end
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
-- A fixed 600 ms wait for the camera put the pointer on other rooms while
-- the camera still moved (slot 411 hovered 404, then 408: firefly82's
-- review, 2026-10-20). So the pointer follows the room until the game
-- itself says it rests there: the ship view's info panel is filled by
-- SetHoverInfo(HoverSlot, ...) for the hovered room and emptied by
-- RemoveInfo (hooked below).
local hover_slot = nil     -- the slot the game's info panel shows, or nil
local hover_action = nil   -- the room's actions, from the same call: { desc, key, costs = { {id, n} }, more = { {desc, key} } }

-- The keyboard key the game maps to an input action, from its own Enhanced
-- Input subsystem (QueryKeysMappedToAction; probe 2026-10-22). The first
-- key that is not a gamepad button: "E", "F", "T", or "LeftMouseButton".
-- Kept per action: the game has no key rebinding in its settings.
local key_cache = {}
local function key_for(a)
    local name = a:GetFName():ToString()
    if key_cache[name] then return key_cache[name] end
    local found = false
    pcall(function()
        local sub = nil
        for _, s in ipairs(FindAllOf("EnhancedInputLocalPlayerSubsystem") or {}) do
            if s:IsValid() and not s:GetFullName():find("Default__", 1, true) then sub = s end
        end
        if not sub then return end
        local keys = sub:QueryKeysMappedToAction(a)
        for _, k in ipairs(keys or {}) do
            local kk = (type(k) == "userdata" and k.get) and k:get() or k
            local n = kk.KeyName:ToString()
            if not n:find("^Gamepad") then found = n break end
        end
    end)
    -- Hits only: a miss while the ship's input context is not applied (a
    -- hover as a window closes) would have left "E:" out for the whole
    -- session (Fable review, 2026-10-22).
    if not found then print("[VoyagerAccess] ship: no keyboard key for " .. name .. "\n"); return nil end
    key_cache[name] = found
    return found
end
local hover_waiters = {}   -- slot -> functions to run once it is hovered
local hover_hooked = false
-- The slot the pointer is being brought to, until the game says it is
-- hovered. The pointer is moved again on each hover change the game reports
-- while the camera travels (SetHoverInfo for another room, RemoveInfo), not
-- every 100 ms: the census of 2026-10-21 showed ForceCameraOnRoom moving the
-- camera with no event of its own (OnCameraChanged never came), but every
-- room passing under the pointer reported (firefly82, 2026-10-21).
local target_slot = nil

-- Moves the pointer onto the hull: "on", or "off" when it is off screen.
local function aim(hull)
    local ok, where = pcall(function()
        local pc = FindFirstOf("PlayerController")
        local size = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportSize(pc)
        local w, h = size.X, size.Y
        local st = {}
        pc:ProjectWorldLocationToScreen(hull:K2_GetActorLocation(), st, false)
        if not (w and h and h > 0 and st.X and st.Y) then return nil end
        if st.X < 0 or st.Y < 0 or st.X > w or st.Y > h then return "off" end
        local r = 350 / 1080 * h   -- the helper's ring radius
        speech.ring_mouse((st.X - w / 2) / r, (st.Y - h / 2) / r)
        return "on"
    end)
    return ok and where or nil
end

local function hull_at(slot)
    for _, r in ipairs(rooms()) do
        if r.hull:BP_GetSlotIndex() == slot then return r.hull end
    end
    return nil
end

local function point_at(hull)
    pcall(function()
        local slot = hull:BP_GetSlotIndex()
        target_slot = slot
        if hover_slot == slot then target_slot = nil return end
        if aim(hull) == "off" then
            print("[VoyagerAccess] ship: room off screen, camera to slot " .. slot .. "\n")
            FindFirstOf("STVConstructionPawn"):ForceCameraOnRoom(slot)
        end
    end)
end

-- The camera has finished moving: ForceCameraOnRoom runs the construction
-- pawn's zoom move, and the pawn's Blueprint gets AudioPassSetZoomLevelEnd
-- when it ends (probe 2026-10-21: ZoomStart at the call, ZoomEnd about
-- 0.47 s later, for both jumps). Only then is the room where the camera put
-- it, so the pointer is set on it once now (its screen position from the
-- game); the game's hover then confirms it. Before, nothing moved the
-- pointer after the camera had arrived, and the room was never said.
local function camera_arrived()
    if not target_slot then return end
    local h = hull_at(target_slot)
    if h then
        print("[VoyagerAccess] ship: camera arrived, pointer to slot " .. target_slot .. "\n")
        aim(h)
    end
end

-- A hover change the game reported (on the next tick of SetHoverInfo or
-- RemoveInfo): the pointer goes after the room again if it is not there.
local function hover_changed()
    if not target_slot then return end
    if hover_slot == target_slot then
        print("[VoyagerAccess] ship: pointer on slot " .. target_slot .. "\n")
        target_slot = nil
        return
    end
    local h = hull_at(target_slot)
    if h then aim(h) end
end

-- Runs fn once the game's info panel shows slot. Only the newest wish per
-- purpose counts (moving on to the next room drops the last one's). A room
-- the pointer never reaches (another ship's pawn, the pointer over a panel,
-- another screen size) would say nothing at all, so after HOVER_FALLBACK_MS
-- fn runs anyway: the room is said without the E text, and the details say
-- "No details shown" (review of firefly82's patch, 2026-10-21; 0.3.67 spoke
-- after 3 s). The camera's move takes about 0.47 s.
local HOVER_FALLBACK_MS = 2000
local function when_hovered(slot, fn, purpose)
    purpose = purpose or "say"
    for s, list in pairs(hover_waiters) do
        if list[purpose] then
            print("[VoyagerAccess] ship: slot " .. s .. " never hovered for " .. purpose .. "\n")
            list[purpose] = nil
        end
    end
    if not hover_hooked then
        -- The panel's class is not loaded yet: at once, as nothing else can
        -- tell when the pointer is there.
        print("[VoyagerAccess] ship: hover hook missing, " .. purpose .. " at once\n")
        return fn()
    end
    if hover_slot == slot then return fn() end
    hover_waiters[slot] = hover_waiters[slot] or {}
    hover_waiters[slot][purpose] = fn
    ExecuteInGameThreadWithDelay(HOVER_FALLBACK_MS, function()
        local list = hover_waiters[slot]
        if not (list and list[purpose] == fn) then return end
        list[purpose] = nil
        -- The pointer stops going after it too: later hover changes pulled
        -- the pointer back to this room for good (GPT review, 2026-10-21).
        if target_slot == slot then target_slot = nil end
        print("[VoyagerAccess] ship: slot " .. slot .. " not hovered in " .. HOVER_FALLBACK_MS .. " ms, " .. purpose .. " anyway\n")
        pcall(fn)
    end)
end

-- What the hovered room's actions do, each with its key, in the game's words
-- and with the quick action's costs or returns, as the info panel shows them
-- ("E: Energie umschalten. F: Verbessern. T: Demontieren"), from
-- SetHoverInfo's QuickAction, QuickActionCostOrReturn and
-- AdditionalDisplayActions. The panel shows each key as an icon
-- (InputIconImage), so the key is said as text. nil when the room has none
-- (a ruined room on a deck without life support).
-- The key is the game's own mapping, not a letter written here: 0.3.70 said
-- "E" for every quick action, also "Raum bauen", which the game puts on the
-- left mouse button (probe 2026-10-22: E for ExecuteRoomSpecific,
-- RepairRoom, ClearDebris; F for UpgradeRoom; T for DemolishRoom;
-- LeftMouseButton for OpenRadialMenu).
local function action_line(desc, key)
    if not (desc and desc ~= "") then return nil end
    -- The left mouse button clicks the room, which the mod's Enter does.
    if key == "LeftMouseButton" then key = require("tr").word("Enter") end
    return key and (key .. ": " .. desc) or desc
end
local function quick_action_text()
    local a = hover_action
    if not a then return nil end
    local out = {}
    local first = action_line(a.desc, a.key)
    if first then
        local costs = {}
        -- In English the game's id was said as it is: "1 BioNeuralGelPack" (demo,
        -- VM, 2026-10-22). The words the room window uses instead.
        local WORDS = { BioNeuralGelPack = { "bio-neural gel pack", "bio-neural gel packs" },
            SciencePoints = { "science points", "science points" }, BorgNanites = { "Borg nanites", "Borg nanites" } }
        for _, c in ipairs(a.costs or {}) do
            local name = require("text").game_resource_name(c.id)
            if not name then
                local w = WORDS[c.id]
                -- tr.word: bio-neural gel pack | bio-neural gel packs | science points | Borg nanites
                name = w and require("tr").word(tonumber(c.n) == 1 and w[1] or w[2]) or c.id
            end
            costs[#costs + 1] = c.n .. " " .. name
        end
        out[#out + 1] = first .. (#costs > 0 and (", " .. table.concat(costs, ", ")) or "")
    end
    for _, m in ipairs(a.more or {}) do
        local line = action_line(m.desc, m.key)
        if line then out[#out + 1] = line end
    end
    if #out == 0 then return nil end
    return table.concat(out, ". ")
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
    -- Said once the game says the pointer rests on the room, so the room
    -- heard is the one E acts on (agreed with firefly82, 2026-10-21: while
    -- the camera travels, E hit rooms passing under the pointer), with what
    -- E does there.
    local slot = r.hull:BP_GetSlotIndex()
    -- A room the game marks as not interactable (bIsInteractable false: the
    -- turbolift, room types 21 and 22) gets no hover at all, no info panel and
    -- no quick action (probe 2026-10-21: the pointer on slot 227 brought no
    -- OnHoveredRoom and no SetHoverInfo), so waiting for one left it silent
    -- (firefly82, 2026-10-21). It is said at once.
    local interactable = true
    pcall(function() interactable = r.hull.bIsInteractable ~= false end)
    if not interactable then
        target_slot = nil
        -- The last room's wish to be said is over too.
        for _, list in pairs(hover_waiters) do list.say = nil end
        print("[VoyagerAccess] ship: " .. text .. "\n")
        speech.say(text, true)
        return
    end
    when_hovered(slot, function()
        local qa = (hover_slot == slot) and quick_action_text() or nil
        local said = qa and (text .. ". " .. qa) or text
        print("[VoyagerAccess] ship: " .. said .. "\n")
        speech.say(said, true)
    end, "say")
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

-- The room is described again each time it is said, from the game's room
-- as it is now: the text made when J opened stayed as it was, so a room
-- built, finished or switched off while the list was open was heard in its
-- old state (review of 0.3.70, 2026-10-22). The list itself (which rooms,
-- in which order) stays as J made it. The made text is kept for a room no
-- longer found.
local function say_jump()
    local it = jump.items[jump.index]
    local text = it.text
    pcall(function()
        for _, r in ipairs(rooms()) do
            if r.deck == it.deck and math.abs(r.y - it.y) < 1 then
                text = describe(r, true)
                break
            end
        end
    end)
    speech.say(string.format("%s, %d of %d", text, jump.index, #jump.items), true)
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
    -- One of the mod's lists at a time (see resources.say).
    require("resources").dismiss()
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

-- Closed without a word when another of the mod's lists opens over it.
function M.list_dismiss()
    jump = nil
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
    -- Read once the game shows this room in its info panel (a room off
    -- screen waits for the camera: the Shuttle bay gave "No details" at
    -- 400 ms with a fixed wait).
    when_hovered(slot, function()
        pcall(function()
            local tip = require("tooltip")
            -- After the fallback the panel may show another room.
            local panel = (hover_slot == slot) and tip.room_panel() or nil
            if not panel then
                speech.say("No details shown for this room", true)
                return
            end
            require("resources").show_details(title, tip.lines(panel))
        end)
    end, "details")
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
    -- opening (Workshop, Q Trial, VM, 2026-10-19). The state hook below says
    -- the new state; saying it here too said it twice (firefly82's review,
    -- 2026-10-20).
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
-- VM the same day). Hooked after the room button's own OnSetState
-- (WBP_Button_RoomSelection), which the game calls once per change; the
-- quest condition listener hooked before arrived 8 times per change and
-- exists only while a quest waits on buildings (firefly82's review,
-- 2026-10-20). A room is said only when its reading differs from the last
-- one seen, so loading a save says nothing and Enter on finished work is
-- said once. Said only in the ship view.
-- The room button tells its own slot (RoomSlot) and passes the new state in
-- the call (OnSetState(State, bPlayAnimation, bIsPaused, EquippedHeroes);
-- probe 2026-10-21: one call per E, State and PrevState in it). A room is
-- said when its state, life support or pause differs from the last call
-- seen for it, so a save loading (one or two calls per room, the first
-- ones) says nothing, and a call that only moves the cycles left on says
-- nothing either (it used to compare the whole reading, cycles and all).
local last_state = {}   -- slot -> "state|life support|paused"
local state_hooked = false
local room_closed_at = -100   -- os.clock() when a room window last closed

local function on_set_state(slot, key, button)
    pcall(function()
        local list = rooms()
        -- The demo's room button has no RoomSlot and no State struct (VM,
        -- 2026-10-22: every change was silent there): the room is the one
        -- whose own button this is, and its reading without the cycles left
        -- stands in for the state.
        if type(slot) ~= "number" then
            for _, r in ipairs(list) do
                local hw = (not r.upper) and r.hull.RoomHullWidget
                if button and hw and hw:IsValid() and hw:GetAddress() == button then
                    slot = r.hull:BP_GetSlotIndex()
                    -- Without the count and its word: "3 cycles" to "1
                    -- cycle" was said as a change (demo, VM, 2026-10-22).
                    if not key then key = (describe(r, false):gsub("%d+%s*[^,%s]*", "")) end
                    break
                end
            end
            if type(slot) ~= "number" or not key then return end
        end
        local before = last_state[slot]
        last_state[slot] = key
        if not before or before == key or not M.active() then return end
        -- A room window's own button says its change, and closing the window
        -- says the room again: Repair there was "Shield Generator,
        -- repairing, 3 cycles" and then "Ship view. Deck 2, Shield
        -- Generator, repairing, 3 cycles" (demo, VM, 2026-10-22).
        -- The change came 3 ms before the window's close notice, with the
        -- window already hidden, so the line waits 100 ms for that notice.
        local okw, win = pcall(function() return require("rooms").window_open() end)
        if (okw and win) or os.clock() - room_closed_at < 1 then return end
        for _, r in ipairs(list) do
            if not r.upper and r.hull:BP_GetSlotIndex() == slot then
                local text = describe(r, false)
                ExecuteInGameThreadWithDelay(100, function()
                    if os.clock() - room_closed_at < 1 then return end
                    print("[VoyagerAccess] ship: changed: " .. text .. "\n")
                    speech.say(text, false)
                end)
                return
            end
        end
    end)
end

-- The room button's class (WBP_Button_RoomSelection_C, loaded at the main
-- menu already: probe 2026-10-21) and the info panel's
-- (WBP_Sideview_InfoPanel_C, loaded with the ship view) are hooked when
-- the game makes their first widget (popups.on_widget), not by trying every
-- 3 s. UE4SS unregisters a mod's hooks itself when the mod is reloaded.
local function install_state(path)
    if state_hooked then return end
    local w = path and StaticFindObject(path)
    if not (w and w:IsValid()) then return end
    local cpath = w:GetClass():GetFullName():match("^%S+%s+(.+)$")
    -- UE4SS calls only the first (pre) callback for this Blueprint function
    -- (VM, 2026-10-20): the values come from the call itself.
    state_hooked = pcall(RegisterHook, cpath .. ":OnSetState", function(ctx, state, _, paused)
        local slot, key, button = nil, nil, nil
        pcall(function()
            local b = ctx:get()
            button = b:GetAddress()
            slot = b.RoomSlot
        end)
        if type(slot) == "number" then
            pcall(function()
                local s = state:get()
                key = tostring(s.State) .. "|" .. tostring(s.bLifeSupportEnabled) .. "|" .. tostring(paused:get())
            end)
            if not key then return end
        end
        -- The button applies the state inside the call: read it next tick.
        ExecuteInGameThread(function() on_set_state(slot, key, button) end)
    end)
    print("[VoyagerAccess] ship: state hook " .. (state_hooked and "installed" or "not installed") .. "\n")
end

-- The info panel's own calls: pre callbacks, so the panel is filled on the
-- next tick, where the slot is recorded and its waiters run.
local function install_hover(path)
    if hover_hooked then return end
    local w = path and StaticFindObject(path)
    if not (w and w:IsValid()) then return end
    local cpath = w:GetClass():GetFullName():match("^%S+%s+(.+)$")
    -- SetHoverInfo(HoverSlot, RoomState, RoomStateDuration, QuickAction,
    -- QuickActionCostOrReturn, QuickActionDuration, AdditionalDisplayActions,
    -- ...) (STVRoomHoverInfoWidget.h).
    local ok = pcall(RegisterHook, cpath .. ":SetHoverInfo", function(_, slot, _, _, qa, costs, _, extra)
        local oks, s = pcall(function() return slot:get() end)
        if not oks then return end
        local action = { costs = {}, more = {} }
        pcall(function()
            local a = qa:get()
            if a and a:IsValid() then
                action.desc = a.ActionDescription:ToString()
                action.key = key_for(a)
            end
        end)
        pcall(function()
            costs:get():ForEach(function(_, e)
                local r = e:get()
                action.costs[#action.costs + 1] = { id = r.ResourceName:ToString(), n = r.ResourceAmount }
            end)
        end)
        -- The panel's other actions (AdditionalDisplayActions, the seventh
        -- parameter): Upgrade on F and Dismantle on T beside the quick
        -- action, each shown with its key icon (probe 2026-10-22, Emergency
        -- Quarters). Never read before; only "E" was said.
        pcall(function()
            extra:get():ForEach(function(_, e)
                local a = e:get()
                if a and a:IsValid() then
                    action.more[#action.more + 1] = { desc = a.ActionDescription:ToString(), key = key_for(a) }
                end
            end)
        end)
        ExecuteInGameThread(function()
            hover_slot = s
            hover_action = action
            local list = hover_waiters[s]
            hover_waiters[s] = nil
            for _, fn in pairs(list or {}) do pcall(fn) end
            pcall(hover_changed)
        end)
    end)
    if ok then
        pcall(RegisterHook, cpath .. ":RemoveInfo", function()
            ExecuteInGameThread(function()
                hover_slot = nil
                hover_action = nil
                pcall(hover_changed)
            end)
        end)
    end
    hover_hooked = ok
    print("[VoyagerAccess] ship: hover hook " .. (ok and "installed" or "not installed") .. "\n")
end

-- The construction pawn's zoom end (camera_arrived), hooked on its
-- Blueprint class when the game makes the pawn, or now if it exists.
local camera_hooked = false
local function install_camera(pawn)
    if camera_hooked or not (pawn and pawn:IsValid()) then return end
    local cpath = pawn:GetClass():GetFullName():match("^%S+%s+(.+)$")
    -- The Blueprint's own event (BP_ConstructionPawn_C implements it); the
    -- native one on STVConstructionPawn is never what runs.
    if not (cpath and cpath:find("^/Game/") and StaticFindObject(cpath .. ":AudioPassSetZoomLevelEnd")) then return end
    camera_hooked = pcall(RegisterHook, cpath .. ":AudioPassSetZoomLevelEnd", function()
        -- A pre hook: the move has ended; the room is read on the next tick.
        ExecuteInGameThread(function() pcall(camera_arrived) end)
    end)
    print("[VoyagerAccess] ship: camera end hook " .. (camera_hooked and "installed" or "not installed") .. "\n")
end

function M.install()
    local popups = require("popups")
    pcall(NotifyOnNewObject, "/Script/STVoyager.STVConstructionPawn", function(o)
        local okp, p = pcall(function() return path_of(o) end)
        if okp and p then
            ExecuteInGameThread(function()
                pcall(function() install_camera(StaticFindObject(p)) end)
            end)
        end
    end)
    for _, pw in ipairs(FindAllOf("STVConstructionPawn") or {}) do
        if pw:IsValid() then pcall(install_camera, pw) break end
    end
    popups.on_widget("WBP_Button_RoomSelection_C", install_state)
    popups.on_widget("WBP_Sideview_InfoPanel_C", install_hover)
    -- A room window's buttons are pressed with the mouse, so when it closes
    -- the pointer is where its last button was, and the game's E acts on
    -- whatever is under it: E right after Escape did nothing until the room
    -- was chosen again, and could have hit another room (VM, 2026-10-21).
    -- The pointer goes back to the room heard, after the window's fade.
    -- Any window, not only a room's: Enter on a window's button is a real
    -- click, so after a Construction Report's CLOSE the pointer sat where
    -- that button was, and E on the Phaser Control Room heard next did
    -- nothing (VM, 2026-10-22).
    popups.on_close(function(_, cls)
        -- Not toasts and map markers: they come and go on their own, have no
        -- button, and never moved the pointer.
        cls = cls or ""
        if cls == "WBP_RoomManagementV2_C" then room_closed_at = os.clock() end
        if cls:find("Toast", 1, true) or cls:find("PoiEventWidget", 1, true) or cls:find("RoomPrompt", 1, true) then return end
        -- Not if the player has chosen another room meanwhile (select()
        -- makes a new selected table; GPT review, 2026-10-21).
        local was = selected
        ExecuteInGameThreadWithDelay(300, function()
            pcall(function()
                if selected ~= was or not M.active() then return end
                -- Not under another window the player opened meanwhile
                -- (Fable review, 2026-10-21).
                for _, wp in ipairs(popups.open_windows()) do
                    if not wp:find("WBP_PoiEventWidget_C", 1, true) and not wp:find("RoomPrompt", 1, true) then return end
                end
                local list = rooms()
                local i = index_of_selected(list)
                if i then point_at(list[i].hull) end
            end)
        end)
    end)
    -- Already made (the main menu has room buttons; a reload in the ship view).
    for cls, fn in pairs({ WBP_Button_RoomSelection_C = install_state, WBP_Sideview_InfoPanel_C = install_hover }) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            local p = w:IsValid() and path_of(w)
            if p and p:find("^/Engine/Transient%.") then pcall(fn, p) break end
        end
    end
end

return M
