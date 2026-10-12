-- The System Map: Left and Right walk the points of interest in the
-- current star system, nearest to Voyager first; Enter scans the selected
-- one. The game offers only the mouse and gamepad here (IMC_System_Map).
--
-- Each point of interest is an STVPointOfInterestBase component on an actor
-- (a planet, a wreck, a debris field). Actors in systems you are not in are
-- hidden. Scanning calls the sector pawn's own TryToScanPOI with the
-- component, what the scan input does for the hovered point.
-- GetDisplayName on the sector tree node returned nothing (2026-10-10), so
-- names come from the actor's class.

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

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

local function name_of(actor)
    local cls = actor:GetClass():GetFName():ToString()
    if NAMES[cls] then return NAMES[cls] end
    local class = cls:match("^BP_STVPlanet_Class(%w+)_C$")
    if class then return "Class " .. class .. " planet" end
    return (cls:gsub("^BP_", ""):gsub("_C$", ""):gsub("_", " "))
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
    if not explored(p.actor) then return "not scanned" end
    local res = resources(p.poi)
    return res ~= "" and res or "scanned"
end

local function voyager()
    for _, v in ipairs(FindAllOf("BP_SectorVoyager_C") or {}) do
        if v:IsValid() and path_of(v):find("PersistentLevel", 1, true) then return v end
    end
    return nil
end

-- Points in the current system as { poi, actor, path, dist }, nearest first.
local function points()
    local ship = voyager()
    local from = ship and ship:K2_GetActorLocation()
    local list = {}
    for _, c in ipairs(FindAllOf("STVPointOfInterestBase") or {}) do
        if c:IsValid() and path_of(c):find("PersistentLevel", 1, true) then
            local a = c:GetOwner()
            if a and a:IsValid() and not a.bHidden then
                local cls = a:GetClass():GetFName():ToString()
                if cls ~= "BP_SectorVoyager_C" and cls ~= "BP_STVSolarSystem_C" then
                    local loc = a:K2_GetActorLocation()
                    local d = from and math.sqrt((loc.X - from.X) ^ 2 + (loc.Y - from.Y) ^ 2) or 0
                    list[#list + 1] = { poi = c, actor = a, path = path_of(a), dist = d }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

local MAP_CONTEXT = nil
function M.active()
    local sub = nil
    for _, s in ipairs(FindAllOf("EnhancedInputLocalPlayerSubsystem") or {}) do
        if s:IsValid() and path_of(s):find("^/Engine/Transient%.") then sub = s end
    end
    if not sub then return false end
    if not (MAP_CONTEXT and MAP_CONTEXT:IsValid()) then
        MAP_CONTEXT = nil
        for _, ctx in ipairs(FindAllOf("InputMappingContext") or {}) do
            if ctx:GetFName():ToString() == "IMC_System_Map" then MAP_CONTEXT = ctx end
        end
    end
    return MAP_CONTEXT ~= nil and sub:HasMappingContext(MAP_CONTEXT, {})
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
    local text = string.format("%s, %s, %d of %d", name_of(p.actor), status(p), i, #list)
    if prefix then text = prefix .. ": " .. text end
    print("[VoyagerAccess] system: " .. text .. "\n")
    speech.say(text, true)
    -- Move the camera to it, as hovering it with the gamepad would.
    local pw = pawn()
    if pw then pcall(function() pw:SetFocusPoint(p.actor) end) end
end

function M.step(dir)
    crumb.at("system: step")
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

local function watch_arrival(name, target, start_d)
    watch_id = watch_id + 1
    local mine = watch_id
    local last, still, left = nil, 0, 300
    local function tick()
        if mine ~= watch_id then return end
        local ok, d = pcall(target_distance, target)
        if not (ok and d) then return end
        if last and math.abs(d - last) <= 5 then still = still + 1 else still = 0 end
        last = d
        if still >= 2 and (not start_d or d <= start_d * 0.9) then
            print("[VoyagerAccess] course: arrived at " .. name .. "\n")
            speech.say("Arrived at " .. name, false)
            return
        end
        left = left - 1
        if left > 0 then ExecuteInGameThreadWithDelay(1000, tick) end
    end
    ExecuteInGameThreadWithDelay(1000, tick)
end

local function verify_course(name, target)
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
            if start_d then
                local d = target_distance(target)
                return d ~= nil and d < start_d - 1
            end
            local v = voyager()
            local at = v and v:K2_GetActorLocation()
            return at ~= nil and ((at.X - x0) ^ 2 + (at.Y - y0) ^ 2) > 1
        end)
        if ok and done then
            print("[VoyagerAccess] course: under way\n")
            watch_arrival(name, target, start_d)
            return
        end
        if tries > 1 then
            ExecuteInGameThreadWithDelay(2000, function() check(tries - 1) end)
            return
        end
        local q = pawn()
        print(string.format("[VoyagerAccess] course: not set (selected=%s travel=%s)\n",
            short(q and q.SelectedActor), short(q and q.PoiSelectedForTravel)))
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
            speech.say(name .. " is already scanned: " .. status(p), true)
            return
        end
        speech.say("Scanning " .. name, true)
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
                    speech.say(res ~= "" and ("Found " .. res) or "Scan complete, nothing found", false)
                else
                    speech.say("The scan did not finish", false)
                end
            end)
        end)
    else
        speech.say("Setting course for " .. name, true)
        pw:SetFocusPoint(p.actor)
        pw:OnSetCourseActionStarted({})
        pw:OnSetCourseActionTriggered({})
        verify_course(name, p.path)
    end
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
    local text = string.format("%s, %s, %d of %d", name_of(p.actor), status(p), i, #list)
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
