-- The System Map: Left and Right walk the points of interest in the
-- current star system, nearest to Voyager first; Enter scans the selected
-- one. The game offers only the mouse and gamepad here (IMC_System_Map).
--
-- Each point of interest is an STVPointOfInterestBase component on an actor
-- (a planet, a wreck, a debris field). Actors in systems you are not in are
-- hidden. Scanning calls the sector pawn's own TryToScanPOI with the
-- component, what the scan input does for the hovered point.
-- GetDisplayName on the sector tree node returned nothing (2026-10-10);
-- names come from the actor's GetTooltipWidgetText (2026-10-14), with the
-- actor's class as the fallback.

local speech = require("speech")
local crumb = require("crumb")

local M = {}

local NAMES = {
    BP_CustomPOILocation_CaretakersArray_C = "Caretaker's array",
    BP_CustomPOILocation_GenericShipWreck_C = "Shipwreck",
    BP_CustomPOILocation_GenericDebrisField_C = "Debris field",
    BP_CustomPOILocation_GenericInterstellarCloud_C = "Interstellar cloud",
    BP_STVShipPOI_C = "Ship",
    BP_STVAsteroid_C = "Asteroid",
    BP_STVPlanet_Story_Ocampa_C = "Ocampa",
}

local selected = nil   -- path of the selected point's owner actor
local found = {}       -- point path -> what its detail window named (note_found)

-- popups.lua reports what a point's detail window names after a scan or a
-- selection ("Kazon-Relora Trade Hub, Dilithium"); the full game's event ids
-- do not say it, so the list said only "scanned" (Q Trial, VM, 2026-10-15).
function M.note_found(summary)
    if selected and summary and summary ~= "" then found[selected] = summary end
end

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

-- The Sector Map's star systems have no names on screen; a world-space
-- widget per system (WBP_SolarSystemWorldSpaceWidget, TargetActor) shows
-- Voyager's icon over the current system and the main mission's badge
-- over the quest's (read 2026-10-14). Those are what tell them apart.
local function system_marks(actor)
    local marks = {}
    pcall(function()
        local apath = actor:GetFullName()
        -- Points in a system have the same kind of widget
        -- (WBP_PoiEventWidget): Ocampa's shows the main mission icon as a
        -- dynamic material, MID_MI_UI_MainMission_... (2026-10-14).
        local widgets = {}
        for _, cls in ipairs({ "WBP_SolarSystemWorldSpaceWidget_C", "WBP_PoiEventWidget_C" }) do
            for _, w in ipairs(FindAllOf(cls) or {}) do widgets[#widgets + 1] = w end
        end
        for _, w in ipairs(widgets) do
            if w:IsValid() and w.TargetActor:IsValid() and w.TargetActor:GetFullName() == apath then
                local wp = path_of(w) .. "."
                for _, x in ipairs(FindAllOf("Image") or {}) do
                    local xp = x:IsValid() and path_of(x)
                    if xp and xp:sub(1, #wp) == wp and require("screen").shown(x) then
                        -- Checked valid before it is read: an unchecked
                        -- brush read crashed the game (2026-10-11, and a
                        -- probe stopped the mod again on 2026-10-14).
                        local ok, r = pcall(function()
                            local ro = x.Brush.ResourceObject
                            if not (ro and ro:IsValid()) then return nil end
                            return ro:GetFName():ToString()
                        end)
                        if ok and r == "MI_UI_Voyager_Icon" then marks[#marks + 1] = "Voyager is here" end
                        if ok and r and r:find("MainMission", 1, true) then marks[#marks + 1] = "main mission" end
                        -- The Planetoid's blue badge, MID_MI_UI_SideMission_...,
                        -- was never mentioned (State of Flux, VM, 2026-10-15).
                        if ok and r and r:find("SideMission", 1, true) then marks[#marks + 1] = "side mission" end
                    end
                end
            end
        end
    end)
    return marks
end

-- A system's number said the way a Starfleet officer would: digit by digit
-- with zero as "oh", "7 1 oh 4" (Casey, 2026-10-11), and ".0" left out.
-- The full game adds a name after the number ("112.0 Vidiian System",
-- 2026-10-14). A sector's systems can differ only after the point
-- (3,520.0 to 3,520.3, State of Flux, 2026-10-15), so any other decimal is
-- said: "3 5 2 oh point 1".
function M.spoken_number(raw)
    local num, dec, rest = raw:gsub(",", ""):match("^(%d+)%.?(%d*)%s*(.-)%s*$")
    if not num then return raw end
    local function digits(s) return (s:gsub("%d", "%0 "):gsub("0 ", "oh "):gsub(" $", "")) end
    local out = digits(num)
    if dec ~= "" and tonumber(dec) ~= 0 then out = out .. " point " .. digits(dec) end
    if rest ~= "" then out = out .. ", " .. rest end
    return out
end

local function name_of(actor)
    local cls = actor:GetClass():GetFName():ToString()
    if cls == "BP_STVSolarSystem_C" then
        local marks = system_marks(actor)
        -- Its hover label names it ("System 3,520.1"); four systems all
        -- read "Star system" (State of Flux, VM, 2026-10-15). A warning
        -- the game gives the system is said too.
        local name = "Star system"
        pcall(function()
            local tip = actor:GetTooltipWidgetText():ToString()
            local n = tip:match("^System%s+(.+)$")
            if n then name = "System " .. M.spoken_number(n) elseif tip ~= "" then name = tip end
        end)
        pcall(function()
            local warn = actor.SystemWarning:ToString()
            -- Not when the name already says it: "Ogla Main Settlement, Ogla
            -- Main Settlement" (Q Trials, VM, 2026-10-15).
            if warn ~= "" and not name:find(warn, 1, true) then marks[#marks + 1] = warn end
        end)
        return name .. (#marks > 0 and (", " .. table.concat(marks, ", ")) or "")
    end
    -- The game's own name, as its hover label shows it: "Class L Planet
    -- with Potential Food Sources" was read from the class as "Planet story
    -- yellow greenish eco zone planet", and ships as "Ship" where the game
    -- says "Vidiian Interceptor" (full game, VM, 2026-10-14). The class is
    -- the fallback.
    local ok, tip = pcall(function() return actor:GetTooltipWidgetText():ToString() end)
    if ok and type(tip) == "string" and tip ~= "" then return tip end
    if NAMES[cls] then return NAMES[cls] end
    local class = cls:match("^BP_STVPlanet_Class(%w+)_C$")
    if class then return "Class " .. class .. " planet" end
    -- Unknown classes: "BP_CustomPOILocation_RepairStation_C" was read as
    -- "CustomPOILocation RepairStation" (Q Trial, VM, 2026-10-14); now
    -- "Repair station".
    local s = cls:gsub("^BP_", ""):gsub("_C$", ""):gsub("^STV", ""):gsub("^CustomPOILocation_", "")
        :gsub("^Generic", ""):gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
    s = s:sub(1, 1) .. s:sub(2):lower()
    return s
end

-- Scanned or not: the actor's IsEventExplored (proven 2026-10-10: true for
-- the scanned Ship and the Caretaker's array, false for the planets still
-- marked with a question mark).
local function explored(actor)
    local ok, v = pcall(function() return actor:IsEventExplored() end)
    return ok and v == true
end

-- What a scanned point holds, from its event IDs
-- ("ResourceEvent_Generated_Deuterium_951" -> Deuterium). Only said once
-- scanned: the IDs exist before the scan and would give the game away.
local function resources(poi)
    local found, seen = {}, {}
    pcall(function()
        poi.EventIds:ForEach(function(_, e)
            local id = e:get():ToString()
            local res = id:match("^ResourceEvent_Generated_(%a+)_%d+$")
            if res and not seen[res] then
                seen[res] = true
                found[#found + 1] = (res:gsub("(%l)(%u)", "%1 %2"))
            end
        end)
    end)
    return table.concat(found, " and ")
end

local function status(p)
    -- The game's gamepad-only Inspect (ActionView.InspectPOIButton,
    -- IA_Sector_InspectPoi; BP_SectorPawn TryToInspectPOI on SelectedActor,
    -- allowed when CanInspectPOI(actor, ESTVScanTarget::PoiView = 4)). None
    -- was inspectable in a Q Trial's first system (VM, 2026-10-15); logged
    -- so the first one met can be explored before the mod offers it.
    pcall(function()
        for _, pw in ipairs(FindAllOf("STVSectorPawn") or {}) do
            if pw:IsValid() and path_of(pw):find("PersistentLevel", 1, true) and pw:CanInspectPOI(p.actor, 4, false) then
                print("[VoyagerAccess] INSPECTABLE: " .. p.path .. "\n")
            end
        end
    end)
    if not explored(p.actor) then return "not scanned" end
    local res = resources(p.poi)
    if res == "" then res = found[p.path] or "" end
    return res ~= "" and res or "scanned"
end

local function voyager()
    for _, v in ipairs(FindAllOf("BP_SectorVoyager_C") or {}) do
        if v:IsValid() and path_of(v):find("PersistentLevel", 1, true) then return v end
    end
    return nil
end

-- Points in the current system as { poi, actor, path, dist }, nearest first.
local order = nil   -- { paths, used }: the list order the player is browsing

local function points()
    local ship = voyager()
    local from = ship and ship:K2_GetActorLocation()
    local list = {}
    for _, c in ipairs(FindAllOf("STVPointOfInterestBase") or {}) do
        if c:IsValid() and path_of(c):find("PersistentLevel", 1, true) then
            local a = c:GetOwner()
            if a and a:IsValid() and not a.bHidden then
                local cls = a:GetClass():GetFName():ToString()
                -- The Sector Map lists star systems, the System Map the
                -- rest (2026-10-14).
                local want = (cls == "BP_STVSolarSystem_C") == M.sector()
                -- Voyager herself; in Q Trials her class is
                -- BP_SectorVoyager_Sandbox_C, listed as "SectorVoyager
                -- Sandbox, scanned" (VM, 2026-10-14).
                if not cls:find("^BP_SectorVoyager") and want then
                    local loc = a:K2_GetActorLocation()
                    local d = from and math.sqrt((loc.X - from.X) ^ 2 + (loc.Y - from.Y) ^ 2) or 0
                    list[#list + 1] = { poi = c, actor = a, path = path_of(a), dist = d }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    -- Nearest first, but frozen while the player is moving through it: two
    -- points at about the same distance swapped as the ship drifted, so Up
    -- from Debris field reached Class D planet, not the Class E planet just
    -- heard, and the course was set for the wrong one (2026-10-14). The
    -- order is kept for 15 s after the last use and while the same points
    -- are listed.
    local now = os.time()
    if order and now - order.used < 15 and #order.paths == #list then
        local rank = {}
        for i, p in ipairs(order.paths) do rank[p] = i end
        local same = true
        for _, p in ipairs(list) do if not rank[p.path] then same = false end end
        if same then
            table.sort(list, function(a, b) return rank[a.path] < rank[b.path] end)
            order.used = now
            return list
        end
    end
    local paths = {}
    for i, p in ipairs(list) do paths[i] = p.path end
    order = { paths = paths, used = now }
    return list
end

local CONTEXTS = {}   -- name -> InputMappingContext
local function context_active(name)
    local sub = nil
    for _, s in ipairs(FindAllOf("EnhancedInputLocalPlayerSubsystem") or {}) do
        if s:IsValid() and path_of(s):find("^/Engine/Transient%.") then sub = s end
    end
    if not sub then return false end
    if not (CONTEXTS[name] and CONTEXTS[name]:IsValid()) then
        CONTEXTS[name] = nil
        for _, ctx in ipairs(FindAllOf("InputMappingContext") or {}) do
            if ctx:GetFName():ToString() == name then CONTEXTS[name] = ctx end
        end
    end
    return CONTEXTS[name] ~= nil and sub:HasMappingContext(CONTEXTS[name], {})
end

-- The Sector Map (IMC_Sector_Map) works like the System Map with star
-- systems for points (2026-10-14: it said nothing at all).
function M.sector()
    return context_active("IMC_Sector_Map")
end

function M.active()
    return context_active("IMC_System_Map") or M.sector()
end

local function pawn()
    for _, p in ipairs(FindAllOf("STVSectorPawn") or {}) do
        if p:IsValid() and path_of(p):find("PersistentLevel", 1, true) then return p end
    end
    return nil
end

local function index_of_selected(list)
    for i, p in ipairs(list) do
        if p.path == selected then return i end
    end
    return nil
end

local menu = nil   -- index into the action list while it is open
-- At either end of the list Up and Down repeat the item, with no extra words
-- (Casey, 2026-10-10). prefix is optional text said first.
local function select(list, i, prefix)
    menu = nil
    local p = list[i]
    selected = p.path
    local name = name_of(p.actor)
    if p.actor:GetClass():GetFName():ToString() ~= "BP_STVSolarSystem_C" then
        local marks = system_marks(p.actor)
        if #marks > 0 then name = name .. ", " .. table.concat(marks, ", ") end
    end
    local text = string.format("%s, %s, %d of %d", name, status(p), i, #list)
    if prefix then text = prefix .. ": " .. text end
    print("[VoyagerAccess] system: " .. text .. "\n")
    speech.say(text, true)
    -- Move the camera to it, as hovering it with the gamepad would.
    local pw = pawn()
    if pw then pcall(function() pw:SetFocusPoint(p.actor) end) end
end

M.last_move = -100   -- os.clock() of the last Up or Down on the map (help.lua)
function M.step(dir)
    crumb.at("system: step")
    M.last_move = os.clock()
    local list = points()
    if #list == 0 then
        speech.say("No points of interest", true)
        return
    end
    local i = index_of_selected(list)
    if not i then return select(list, 1) end
    if not list[i + dir] then
        return select(list, i)
    end
    select(list, i + dir)
end

-- Home and End: the nearest and the farthest point.
function M.edge(last)
    local list = points()
    if #list == 0 then return end
    select(list, last and #list or 1)
end

-- Enter on a point opens a short list of actions (Casey: lists move with
-- Up and Down, 2026-10-10). Scan is proven (it revealed Deuterium,
-- 2026-10-10). Set course puts the camera on the point, as gamepad hovering
-- does, then fires the set-course input's own handlers: proven 2026-10-11,
-- Voyager moved toward the selected Class P planet.
local ACTIONS = { "Scan", "Set course" }

function M.menu_open()
    return menu ~= nil
end

local function selected_point()
    local list = points()
    local i = index_of_selected(list)
    return i and list[i] or nil
end

-- Set course sometimes did nothing (Casey, 2026-10-11, not caught in a
-- log; it worked on the next try). The game has a silent travel error
-- (STVUserError_CanTravelSilent, SetCourseErrorSilent) next to the ones it
-- shows as toasts, and set course is a hold-to-charge input the mod fires
-- in one go. Cause not known yet, so: watch whether Voyager starts moving
-- or the pawn has a travel target, say so if neither happens within six
-- seconds, and log what the pawn had selected for the next diagnosis.
local function short(o)
    return (o and o:IsValid()) and o:GetFullName():match("([^%.]+)$") or "none"
end

-- "Arrived at Shipwreck" once Voyager is there (Casey, 2026-10-11: arriving
-- where nothing opens said nothing). Voyager circles a point once it gets
-- there, so its position keeps changing but its distance does not (900 from
-- a Class Y planet for 30 s, 2026-10-11). Arrived means the distance to the
-- target held within 5 units for two checks a second apart and is clearly
-- less than at the start (the game can pause mid-flight for a message). The
-- watch gives up after five minutes; a new course replaces it.
local watch_id = 0

local function target_distance(target)
    local v = voyager()
    local a = v and v:K2_GetActorLocation()
    local t = StaticFindObject(target)
    local b = t and t:IsValid() and t:K2_GetActorLocation()
    if not (a and b) then return nil end
    return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
end

-- The trip under way, for L: { name, start_d, d, still }. A trip took
-- several minutes in the VM (2026-10-14) and the watch gave up after five
-- without a word, so a long trip and a stalled game sounded the same
-- (Casey asked how to tell them apart). It now says "Under way", "Halfway
-- to", and keeps watching for up to 30 minutes; L reports the progress and
-- says when the ship is not moving.
local travel = nil

local function watch_arrival(name, target, start_d)
    watch_id = watch_id + 1
    local mine = watch_id
    local last, still, left, halfway = nil, 0, 1800, false
    travel = { name = name, start_d = start_d, d = start_d, still = 0 }
    local function tick()
        if mine ~= watch_id then return end
        -- An event at the destination opened before the ship stopped, and
        -- "Halfway" and "Arrived" were then said over it (2026-10-14). The
        -- event says where you are; stop watching quietly.
        local oke, event_open = pcall(function()
            for _, p in ipairs(require("popups").open_windows()) do
                if p:find("WBP_POIMultipleChoice_C", 1, true) then return true end
            end
            return false
        end)
        -- An event can also open mid-trip ("Lost Starship" after "Halfway",
        -- full game, VM, 2026-10-15), and the ship then arrived with nothing
        -- said. While the ship is still well short of the target, the watch
        -- waits out the event and carries on. (The journey reports "not
        -- travelling" while the event is open, so distance decides; the
        -- ship stops 900 from a point, so more than 1200 is still on the way.)
        if oke and event_open then
            local okd2, d2 = pcall(target_distance, target)
            local far = okd2 and d2 and d2 > 1200
            if far then
                if not travel.paused then
                    travel.paused = true
                    print("[VoyagerAccess] course: event opened on the way to " .. name .. ", waiting\n")
                end
                last, still = nil, 0
                left = left - 1
                if left > 0 then ExecuteInGameThreadWithDelay(1000, tick) else travel = nil end
                return
            end
            travel = nil
            print("[VoyagerAccess] course: event opened at " .. name .. "\n")
            return
        end
        travel.paused = nil
        -- A conversation on arrival ("Harry Kim: Captain, we reached our
        -- destination. Orders?") came before "Arrived at", which was then
        -- said over its choices (Casey's machine, 2026-10-15). The
        -- conversation says where you are; stop quietly once the ship has
        -- stopped and it is up.
        local okd, talking = pcall(function() return require("dialogue").active() ~= nil end)
        if okd and talking then
            local okd3, d3 = pcall(target_distance, target)
            local far = okd3 and d3 and d3 > 1200
            if not far then
                travel = nil
                print("[VoyagerAccess] course: conversation opened at " .. name .. "\n")
                return
            end
        end
        local ok, d = pcall(target_distance, target)
        if not (ok and d) then travel = nil return end
        if last and math.abs(d - last) <= 5 then still = still + 1 else still = 0 end
        last = d
        -- A mission offer (WBP_MultipleChoiceWidget) pauses the trip, and
        -- the stopped ship was taken for an arrival: "Arrived" was said 5 s
        -- into an 8-cycle trip (full game, VM, 2026-10-14). The game still
        -- reports the trip as under way then.
        local okj, moving = pcall(function()
            local j = FindFirstOf("STVJourneySubsystem")
            return j and j:IsValid() and j:IsTravelling()
        end)
        if okj and moving == true then still = 0 end
        travel.d, travel.still = d, still
        -- A battle that interrupts the trip: "Halfway to" and "Arrived at"
        -- were said over the battle setup (Q Trial, VM, 2026-10-14).
        local okb, battle = pcall(function() return require("combat").screen_up() end)
        battle = okb and battle
        if still >= 2 and (not start_d or d <= start_d * 0.9) then
            travel = nil
            print("[VoyagerAccess] course: arrived at " .. name .. (battle and " (in battle, not said)" or "") .. "\n")
            if not battle then speech.say("Arrived at " .. name, false) end
            return
        end
        if start_d and start_d > 0 and not halfway and d <= start_d / 2 then
            halfway = true
            if not battle then speech.say("Halfway to " .. name, false) end
        end
        left = left - 1
        if left > 0 then ExecuteInGameThreadWithDelay(1000, tick) else travel = nil end
    end
    ExecuteInGameThreadWithDelay(1000, tick)
end

-- For L: "Traveling to Class E planet, 40 percent of the way", or nil.
function M.travel_status()
    if not travel then return nil end
    local text = "Traveling to " .. travel.name
    if travel.start_d and travel.start_d > 0 and travel.d then
        local pct = math.floor((1 - travel.d / travel.start_d) * 100 + 0.5)
        text = text .. string.format(", %d percent of the way", math.max(0, math.min(100, pct)))
    end
    if travel.still >= 5 then text = text .. ", not moving" end
    return text
end

local fire_course   -- defined after run(); verify_course retries through it

-- Sets a course with STVJourneySubsystem:DeclareTravel(ship, point), when
-- CanTravel allows it. True when the call was made; it then checks that the
-- trip started, says "Under way" and watches for the arrival.
function M.declare_travel(name, target, start_d)
    local ok, started = pcall(function()
        local j = FindFirstOf("STVJourneySubsystem")
        local ship = voyager()
        local poi = nil
        for _, c in ipairs(FindAllOf("STVPointOfInterestBase") or {}) do
            if c:IsValid() and path_of(c):find("PersistentLevel", 1, true) then
                local a = c:GetOwner()
                if a and a:IsValid() and path_of(a) == target then poi = c end
            end
        end
        if not (j and j:IsValid() and ship and poi) then return false end
        if not j:CanTravel(ship, poi, {}) then return false end
        print("[VoyagerAccess] course: DeclareTravel " .. name .. "\n")
        j:DeclareTravel(ship, poi)
        return true
    end)
    if not (ok and started) then
        print("[VoyagerAccess] course: DeclareTravel not possible (" .. tostring(started) .. ")\n")
        return false
    end
    ExecuteInGameThreadWithDelay(1500, function()
        pcall(function()
            local j = FindFirstOf("STVJourneySubsystem")
            local d = target_distance(target)
            local moving = j and j:IsValid() and j:IsTravelling()
            if moving or (d and start_d and d < start_d - 1) or (d and d <= 1000) then
                print("[VoyagerAccess] course: under way (DeclareTravel)\n")
                speech.say("Under way to " .. name, false)
                watch_arrival(name, target, start_d)
            else
                speech.say("The course for " .. name .. " was not set. Press Enter and choose Set course again.", false)
            end
        end)
    end)
    return true
end
local function verify_course(name, target, attempt)
    local ship = voyager()
    local start = ship and ship:K2_GetActorLocation()
    if not start then return end
    local x0, y0 = start.X, start.Y
    local pw = pawn()
    local ok0, d0 = pcall(target_distance, target)
    local start_d = ok0 and d0 or nil
    print(string.format("[VoyagerAccess] course: selected=%s travel=%s distance=%s\n",
        short(pw and pw.SelectedActor), short(pw and pw.PoiSelectedForTravel), tostring(start_d)))
    -- Under way means getting closer to the chosen point, not just moving.
    -- (A stale SelectedActor, seen in Pawsi's log, does not redirect the
    -- course: tested 2026-10-11 with Class P selected and Class Y chosen,
    -- Voyager flew to Class Y.)
    local function check(tries)
        local ok, done = pcall(function()
            -- Already there: Ocampa was 900 away and its dialogue opened at
            -- once, and the mod said the course was not set and set it
            -- again during the dialogue (2026-10-14). A dialogue or an
            -- event opening means the trip is over.
            if require("dialogue").active() then return "arrived" end
            for _, p in ipairs(require("popups").open_windows()) do
                if p:find("WBP_POIMultipleChoice_C", 1, true) then return "arrived" end
            end
            -- The game's own travel target, when it can be read: a getting-
            -- closer test alone said "under way" while the planet's orbit
            -- brought it nearer and no course was set (2026-10-14).
            local q = pawn()
            local t = q and q.PoiSelectedForTravel
            local okt, owner = pcall(function()
                if not (t and t:IsValid()) then return "" end
                return path_of(t:GetOwner())
            end)
            if okt then return owner == target end
            if start_d then
                local d = target_distance(target)
                return d ~= nil and d < start_d - 1
            end
            local v = voyager()
            local at = v and v:K2_GetActorLocation()
            return at ~= nil and ((at.X - x0) ^ 2 + (at.Y - y0) ^ 2) > 1
        end)
        if ok and done == "arrived" then
            print("[VoyagerAccess] course: at " .. name .. " (dialogue or event)\n")
            return
        end
        if ok and done then
            print("[VoyagerAccess] course: under way\n")
            speech.say("Under way to " .. name, false)
            watch_arrival(name, target, start_d)
            return
        end
        if tries > 1 then
            ExecuteInGameThreadWithDelay(2000, function() check(tries - 1) end)
            return
        end
        local q = pawn()
        print(string.format("[VoyagerAccess] course: not set (selected=%s travel=%s, attempt %s)\n",
            short(q and q.SelectedActor), short(q and q.PoiSelectedForTravel), tostring(attempt)))
        -- Within arrival range (900, seen at Ocampa and at a Class Y planet
        -- after its event): the game sets no course because Voyager is
        -- there; "was not set" sent Casey round again (2026-10-14).
        if start_d and start_d <= 1000 then
            speech.say("Voyager is already at " .. name, false)
            return
        end
        if attempt == 1 then
            fire_course(name, target, 2)
            return
        end
        -- Last: the journey's own DeclareTravel, with no mouse at all. A
        -- forum player's game never picked up the point under the cursor
        -- (2560x1600 at 100 percent, one screen, cursor exactly on the
        -- point, "selected=none" every time, 2026-10-16); DeclareTravel
        -- flew Voyager there with the cursor parked in a corner (demo, VM).
        -- Only when the game's own CanTravel agrees.
        if attempt == 2 and M.declare_travel(name, target, start_d) then return end
        speech.say("The course for " .. name .. " was not set. Press Enter and choose Set course again.", false)
    end
    ExecuteInGameThreadWithDelay(2000, function() check(3) end)
end

local function run(action, p)
    local pw = pawn()
    if not pw then return end
    local name = name_of(p.actor)
    print("[VoyagerAccess] system: " .. action:lower() .. " " .. name .. "\n")
    if action == "Scan" then
        if explored(p.actor) then
            -- With no resources, status is just "scanned": "Caretaker's
            -- array is already scanned: scanned" (2026-10-14).
            local s = status(p)
            speech.say(name .. " is already scanned" .. (s ~= "scanned" and (": " .. s) or ""), true)
            return
        end
        speech.say("Scanning " .. name, true)
        require("popups").reread_for("POIDetailView")
        pw:TryToScanPOI(p.poi)
        -- The result shows at once (Ship revealed Deuterium within a second).
        -- Look the point up again by path: objects are never kept across
        -- ticks (a kept one went stale and crashed UE4SS, 2026-10-10).
        local path = p.path
        ExecuteInGameThreadWithDelay(700, function()
            pcall(function()
                local q
                for _, x in ipairs(points()) do if x.path == path then q = x end end
                if not q then return end
                if explored(q.actor) then
                    local res = resources(q.poi)
                    if res == "" then res = found[q.path] or "" end
                    -- The full game's event IDs are not ResourceEvent_Generated_*,
                    -- so "nothing found" followed a panel listing Tritanium
                    -- (Q Trial, VM, 2026-10-14); the panel says what was found.
                    speech.say(res ~= "" and ("Found " .. res) or "Scan complete", false)
                else
                    speech.say("The scan did not finish", false)
                end
            end)
        end)
    else
        speech.say("Setting course for " .. name, true)
        fire_course(name, p.path, 1)
    end
end

-- Set course takes its target from under the mouse cursor, not from the
-- camera: with the cursor in a corner it never set a course, and with it in
-- the middle (where SetFocusPoint puts the point) it did (2026-10-14, the
-- VM). The helper centres the cursor. The camera glides to the point, so
-- the course is fired after 900 ms (300 ms failed once for the Shipwreck),
-- and a course that did not take is tried once more before the player is
-- told.
-- With the camera on the target, the cursor goes on the target. When
-- Voyager sits on top of it (Ocampa after the first away team: "Fly back
-- to Ocampa" while 900 away), the centre hit Voyager and no course was set,
-- and the story could not go on (VM, 2026-10-14). Then the cursor is put on
-- the target's own screen position, nudged away from Voyager.
-- With click, the helper also clicks there: a Ship Wreck beside Voyager
-- took no course from the cursor alone, twice, and took it once a real
-- click had selected it (demo, VM, 2026-10-15). Used for the second try.
local function aim_at(actor, click)
    local ok = pcall(function()
        local pc = FindFirstOf("PlayerController")
        local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local voy = nil
        for _, cls in ipairs({ "BP_SectorVoyager_C", "BP_SectorVoyager_Sandbox_C" }) do
            for _, x in ipairs(FindAllOf(cls) or {}) do
                if x:IsValid() and x:GetFullName():find("PersistentLevel", 1, true) then voy = x end
            end
        end
        if not (pc and lib and voy) then error("no camera") end
        local size = lib:GetViewportSize(pc)
        local w, h = size.X, size.Y
        local st, sv = {}, {}
        pc:ProjectWorldLocationToScreen(actor:K2_GetActorLocation(), st, false)
        pc:ProjectWorldLocationToScreen(voy:K2_GetActorLocation(), sv, false)
        if not (w and h and h > 0) then error("no size") end
        -- Off screen: leave it to the camera and the centre.
        if not (st.X and st.Y and st.X >= 0 and st.Y >= 0 and st.X <= w and st.Y <= h) then error("off screen") end
        -- Always on the target itself: the camera did not always move to it
        -- (Class Y planet stayed at the side and the centre hit Voyager,
        -- VM, 2026-10-14). Nudged away from Voyager when they are close.
        local dx, dy = st.X - sv.X, st.Y - sv.Y
        local len = math.sqrt(dx * dx + dy * dy)
        local tx, ty = st.X, st.Y
        if len <= 80 then
            if len < 1 then dx, dy, len = 1, 0, 1 end
            tx, ty = st.X + dx / len * 12, st.Y + dy / len * 12
        end
        -- Under the top status bar (bottom edge about 100 of 1080): the click
        -- hit the bar and opened its CYCLES tip, which then covered the map
        -- below it, and no course was set. The camera stays on Voyager here
        -- (forced follow after the story), so aim at the planet's lower
        -- edge, below the bar; that set the course (full game, State of
        -- Flux planet at y 106, VM, 2026-10-14).
        local bar = 0.11 * h
        if ty < bar and ty > bar - 30 / 1080 * h then ty = bar + 4 / 1080 * h end
        local r = 350 / 1080 * h   -- the helper's ring radius
        print(string.format("[VoyagerAccess] course: aiming at %.0f,%.0f%s\n", tx, ty, click and ", clicking" or ""))
        if click then
            speech.ring_click((tx - w / 2) / r, (ty - h / 2) / r)
        else
            speech.ring_mouse((tx - w / 2) / r, (ty - h / 2) / r)
        end
    end)
    if not ok then speech.center_mouse() end
end

-- Whether the actor is on screen now; nil when that cannot be told, which
-- must not count as off screen (it would zoom out every time).
local function on_screen(actor)
    local ok, yes = pcall(function()
        local pc = FindFirstOf("PlayerController")
        local size = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportSize(pc)
        local st = {}
        pc:ProjectWorldLocationToScreen(actor:K2_GetActorLocation(), st, false)
        if st.X == nil or st.Y == nil then return nil end
        return st.X >= 0 and st.Y >= 0 and st.X <= size.X and st.Y <= size.Y
    end)
    if not ok then return nil end
    return yes
end

fire_course = function(name, path, attempt, zooms)
    local q0 = pawn()
    local actor = StaticFindObject(path)
    if q0 and actor and actor:IsValid() then pcall(function() q0:SetFocusPoint(actor) end) end
    speech.center_mouse()
    ExecuteInGameThreadWithDelay(900, function()
        pcall(function()
            local q = pawn()
            if not q then return end
            local a = StaticFindObject(path)
            -- After a story scene the camera is held on Voyager (bForceFollow)
            -- and SetFocusPoint does not move it: Sikaris was below the
            -- screen, the cursor went to the centre, hit Voyager, and no
            -- course was set twice (State of Flux, VM, 2026-10-15). A sighted
            -- player zooms out; so does the mod, until the point is on
            -- screen (TargetZoom 29297 to 70000 brought Sikaris in).
            zooms = zooms or 0
            if a and a:IsValid() and zooms < 3 and on_screen(a) == false then
                local okz = pcall(function() q.TargetZoom = math.min((q.TargetZoom or 30000) * 2, 250000) end)
                if okz then
                    print("[VoyagerAccess] course: zooming out, target off screen\n")
                    ExecuteInGameThreadWithDelay(600, function() fire_course(name, path, attempt, zooms + 1) end)
                    return
                end
            end
            local click = attempt > 1
            if a and a:IsValid() then aim_at(a, click) end
            -- The helper's click takes about 150 ms (hover, press, release).
            ExecuteInGameThreadWithDelay(click and 500 or 150, function()
                pcall(function()
                    local q2 = pawn()
                    if not q2 then return end
                    q2:OnSetCourseActionStarted({})
                    q2:OnSetCourseActionTriggered({})
                    verify_course(name, path, attempt)
                end)
            end)
        end)
    end)
end

function M.enter()
    crumb.at("system: enter")
    local p = selected_point()
    if not p then
        speech.say("Nothing selected. Use Up and Down Arrow to choose a point of interest.", true)
        return
    end
    if not menu then
        menu = 1
        speech.say(ACTIONS[1] .. ", 1 of " .. #ACTIONS, true)
        return
    end
    local action = ACTIONS[menu]
    menu = nil
    run(action, p)
end

-- For L (where am I): the selected point, or nil.
function M.where()
    local list = points()
    local i = index_of_selected(list)
    if not i then return nil end
    local p = list[i]
    local name = name_of(p.actor)
    if p.actor:GetClass():GetFName():ToString() ~= "BP_STVSolarSystem_C" then
        local marks = system_marks(p.actor)
        if #marks > 0 then name = name .. ", " .. table.concat(marks, ", ") end
    end
    local text = string.format("%s, %s, %d of %d", name, status(p), i, #list)
    if menu then text = text .. ". Action list open: " .. ACTIONS[menu] end
    return text
end

-- Up and Down inside the action list.
function M.menu_step(dir)
    local i = menu + dir
    if not ACTIONS[i] then return end
    menu = i
    speech.say(ACTIONS[i] .. ", " .. i .. " of " .. #ACTIONS, true)
end

function M.menu_edge(last)
    menu = last and #ACTIONS or 1
    speech.say(ACTIONS[menu] .. ", " .. menu .. " of " .. #ACTIONS, true)
end

function M.menu_close()
    if not menu then return false end
    menu = nil
    speech.say("Closed", true)
    return true
end

function M.preview()
    local out = {}
    for i, p in ipairs(points()) do out[#out + 1] = i .. " " .. name_of(p.actor) .. ", " .. status(p) end
    return tostring(M.active()) .. " | " .. table.concat(out, ", ")
end

return M
