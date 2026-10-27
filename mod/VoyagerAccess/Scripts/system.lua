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
-- The map's markers, as the game makes them (popups.on_widget, the same
-- pass over new widgets as the windows'): paths of the live
-- WBP_PoiEventWidget and WBP_SolarSystemWorldSpaceWidget widgets. Each says
-- its point in its own TargetActor field.
local map_widgets = {}
local function add_map_widget(p)
    if p:find("^/Engine/Transient%.") then map_widgets[#map_widgets + 1] = p end
end

function M.install()
    local popups = require("popups")
    popups.on_widget("WBP_PoiEventWidget_C", add_map_widget)
    popups.on_widget("WBP_SolarSystemWorldSpaceWidget_C", add_map_widget)
    -- The game's detail panel read after Enter selected a point (M.enter).
    popups.on_read(function(p, cls)
        if tostring(p):find("POIDetailView", 1, true) or tostring(cls):find("POIDetailView", 1, true) then
            pcall(M.on_panel_read)
        end
    end)
    -- Travel from the game's own signals (hooks installed once).
    pcall(function() M.hook_travel() end)
end

-- The markers of one point, gone ones dropped.
local function widgets_of(apath)
    local out, keep = {}, {}
    for _, p in ipairs(map_widgets) do
        local w = StaticFindObject(p)
        if w and w:IsValid() then
            keep[#keep + 1] = p
            local ok, same = pcall(function() return w.TargetActor:IsValid() and w.TargetActor:GetFullName() == apath end)
            if ok and same then out[#out + 1] = w end
        end
    end
    map_widgets = keep
    return out
end

-- The images inside one marker, from its own widget tree. It used to look
-- at every Image in the game (10080 on a System Map) and keep those under
-- the marker: 55 ms on each arrow key, held by the game (map audit,
-- 2026-10-21). The same images, found from the marker down.
local function images_in(root)
    local IMG = StaticFindObject("/Script/UMG.Image")
    local PANEL = StaticFindObject("/Script/UMG.PanelWidget")
    local UW = StaticFindObject("/Script/UMG.UserWidget")
    local out = {}
    local function walk(w, depth)
        if depth > 30 or not (w and w:IsValid()) then return end
        -- Hidden branches are not walked: walking a hidden panel's children
        -- crashed the game (screen.texts_in, probe 2026-10-20), and only
        -- shown images are used (review of firefly82's patch, 2026-10-21).
        if not w:IsVisible() then return end
        if w:IsA(IMG) then
            out[#out + 1] = w
        elseif w:IsA(UW) then
            local tree = w.WidgetTree
            if tree and tree:IsValid() and tree.RootWidget then walk(tree.RootWidget, depth + 1) end
        elseif w:IsA(PANEL) then
            for i = 0, w:GetChildrenCount() - 1 do walk(w:GetChildAt(i), depth + 1) end
        end
    end
    walk(root, 0)
    return out
end

local POI_CLASS = nil
local function poi_of(actor)
    POI_CLASS = POI_CLASS or StaticFindObject("/Script/STVoyager.STVPointOfInterestBase")
    local ok, c = pcall(function() return actor:GetComponentByClass(POI_CLASS) end)
    if ok and c and c:IsValid() then return c end
    return nil
end

local function system_marks(actor)
    local marks = {}
    pcall(function()
        local apath = actor:GetFullName()
        -- Points in a system have the same kind of widget
        -- (WBP_PoiEventWidget): Ocampa's shows the main mission icon as a
        -- dynamic material, MID_MI_UI_MainMission_... (2026-10-14).
        for _, w in ipairs(widgets_of(apath)) do
            do
                -- The countdown a point shows under its marker while a hero
                -- is stationed there or it is locked down
                -- (HarvestTimeRemaining_TXT; firefly82's parity check,
                -- 2026-10-18). Said only while the screen shows it.
                pcall(function()
                    local t = w.HarvestTimeRemaining_TXT
                    if t and t:IsValid() and require("screen").shown(t) then
                        local n = tonumber((t:GetText():ToString():gsub("%D", "")))
                        if n then marks[#marks + 1] = n .. (n == 1 and " cycle left" or " cycles left") end
                    end
                end)
                for _, x in ipairs(images_in(w)) do
                    if require("screen").shown(x) then
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
    -- The badge is not always drawn: the campaign's "Examine the Kazon
    -- wreckage" Shipwreck and Q Trials mission points had none (VM,
    -- 2026-10-16). A point's own EventIds name its story line
    -- ("QuestLines.Maneuvers -> DA_Main_02_..."), and the event subsystem
    -- says which one is live (Activatable).
    pcall(function()
        local have = {}
        for _, m in ipairs(marks) do have[m] = true end
        local es = FindFirstOf("STVEventSubsystem")
        local E = StaticFindObject("/Script/STVoyager.ESTVEventState")
        -- The point's own component (the map audit found it the same as
        -- the one a search of every point gave).
        local poi = poi_of(actor)
        if not (poi and es and E) then return end
        poi.EventIds:ForEach(function(_, v)
            local id = v:get()
            local s = id:ToString()
            local kind = s:find("-> DA_Main_", 1, true) and "main mission" or (s:find("-> DA_Side_", 1, true) and "side mission") or nil
            if kind and not have[kind] then
                local okst, st = pcall(function() return E:GetNameByValue(es:GetEventStateById(id)):ToString() end)
                if okst and st and st:find("Activatable", 1, true) then
                    have[kind] = true
                    marks[#marks + 1] = kind
                end
            end
        end)
    end)
    return marks
end

-- A system's number said the way a Starfleet officer would: digit by digit
-- with zero as "oh", "7 1 oh 4" (Casey, 2026-10-11), and ".0" left out.
-- The full game adds a name after the number ("112.0 Vidiian System",
-- 2026-10-14). A sector's systems can differ only after the point
-- (3,520.0 to 3,520.3, State of Flux, 2026-10-15), so any other decimal is
-- said: "3 5 2 oh point 1".
-- The point after the number is the last separator before one final digit:
-- German groups thousands with a point, "4.048.0", which was split at the
-- first point and said "4 point oh 4 8, .0" (German game, 2026-10-18).
function M.spoken_number(raw)
    local numtxt, rest = raw:match("^(%d[%d%.,]*)%s*(.-)%s*$")
    if not numtxt then return raw end
    -- The point details' system text is "2,208.1", a line break, then the
    -- name, and the clean-up makes the break ". ": the number's own final
    -- point lost its decimal, "2 2 oh 8 1" and "2 9 2 8 oh" (Q Trials, VM,
    -- 2026-10-22).
    numtxt = numtxt:gsub("[%.,]+$", "")
    local num, dec = numtxt:match("^(.-)[%.,](%d)$")
    if not num then num, dec = numtxt, "" end
    num = num:gsub("[%.,]", "")
    if num == "" then return raw end
    -- "oh" is an English word (Casey's choice for English, 2026-10-11); in
    -- another language the digit 0 is read by the synthesizer. The decimal
    -- is the mod's word in the game's language (the tables' "point":
    -- "Komma", "virgule"): the game's own mark with a space after it read
    -- as the end of a sentence, "System 3 9 6 8. 1" (German, firefly82,
    -- 2026-10-21).
    local okl, english = pcall(function() return require("language").english() end)
    english = not okl or english ~= false
    local function digits(s)
        s = s:gsub("%d", "%0 ")
        if english then s = s:gsub("0 ", "oh ") end
        return (s:gsub(" $", ""))
    end
    local out = digits(num)
    if dec ~= "" and tonumber(dec) ~= 0 then
        out = out .. " " .. (english and "point" or require("tr").word("point")) .. " " .. digits(dec)
    end
    if rest ~= "" then out = out .. ", " .. rest end
    return out
end

-- Inside a nebula the game names every point and star system "Unknown"
-- (its selection label said "Unknown, 3 cycles Away" for a Class P planet
-- and for a system the mod called by name; Nebula Sector, Q Trial, VM,
-- 2026-10-18). Inside means within a nebula phenomenon's sphere.
-- The game's own word for such a point, in its language: the localization
-- entry STVSectorActor / UnScannableName ("Unknown", German "Unbekannt";
-- found in the game's language files, 2026-10-20). "Unknown" if the lookup
-- fails.
local function unknown_word()
    local word = "Unknown"
    pcall(function()
        local lib = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
        local out = {}
        if lib:FindTextInLocalizationTable("STVSectorActor", "UnScannableName", out, "") then
            local s = out.OutText:ToString()
            if s ~= "" then word = s end
        end
    end)
    return word
end

local function in_nebula(actor)
    local ok, hidden = pcall(function()
        local loc = actor:K2_GetActorLocation()
        for _, n in ipairs(FindAllOf("STVPhenomenon") or {}) do
            if n:IsValid() and n:GetClass():GetFName():ToString():find("Nebula", 1, true) then
                local s = n.Sphere
                local c = s:K2_GetComponentLocation()
                local d = math.sqrt((loc.X - c.X) ^ 2 + (loc.Y - c.Y) ^ 2 + (loc.Z - c.Z) ^ 2)
                if d < s:GetScaledSphereRadius() then return true end
            end
        end
        return false
    end)
    return ok and hidden
end

-- The storms, fields and clouds a point lies in, by the game's own names
-- (ST_Phenomena_SharedStrings, PhenomenonName...): the map draws them, and a
-- blind player could not tell the Class M planet sat in an ion storm that
-- ate the warp core while waiting there (Friendship One, VM, 2026-10-21).
-- Class name part to the string table's key.
local PHENOMENA = { AsteroidField = "AsteroidField", ContaminationCloud = "ContaminatedCloud", IonStorm = "IonStorm",
    Nebula = "Nebula", NeutronicStorm = "NeutronicStorm", PlasmaStorm = "PlasmaStorm" }
local phenomenon_names = {}
local function phenomenon_name(key)
    if phenomenon_names[key] then return phenomenon_names[key] end
    local word = nil
    pcall(function()
        local lib = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
        local out = {}
        if lib:FindTextInLocalizationTable("ST_Phenomena_SharedStrings", "PhenomenonName" .. key, out, "") then
            local s = out.OutText:ToString()
            if s ~= "" then word = s end
        end
    end)
    word = word or (key:gsub("(%l)(%u)", "%1 %2"))
    phenomenon_names[key] = word
    return word
end

local function phenomena_at(actor)
    local found = {}
    pcall(function()
        local loc = actor:K2_GetActorLocation()
        for _, n in ipairs(FindAllOf("STVPhenomenon") or {}) do
            if n:IsValid() and n:GetFullName():find("PersistentLevel", 1, true) then
                local cls = n:GetClass():GetFName():ToString()
                local part = cls:match("^BP_STVPhenomenon_(%a-)%u?_C$") or cls:match("^BP_STVPhenomenon_(%a+)_C$")
                local key = part and PHENOMENA[part]
                if key then
                    local s = n.Sphere
                    local c = s:K2_GetComponentLocation()
                    local d = math.sqrt((loc.X - c.X) ^ 2 + (loc.Y - c.Y) ^ 2 + (loc.Z - c.Z) ^ 2)
                    if d < s:GetScaledSphereRadius() then
                        local name = phenomenon_name(key)
                        local dup = false
                        for _, f in ipairs(found) do if f == name then dup = true end end
                        if not dup then found[#found + 1] = name end
                    end
                end
            end
        end
    end)
    return found
end

-- ", inside Ion Storm" or "".
local function inside_text(actor)
    -- Points of the open system only: a star system on the Sector Map is
    -- not in the same space as the system's phenomena.
    local okc, cls = pcall(function() return actor:GetClass():GetFName():ToString() end)
    if not okc or cls == "BP_STVSolarSystem_C" then return "" end
    local found = phenomena_at(actor)
    if #found == 0 then return "" end
    return ", " .. require("tr").fill("inside {s}", table.concat(found, ", "))
end

local function name_of(actor)
    local cls = actor:GetClass():GetFName():ToString()
    if cls == "BP_STVSolarSystem_C" then
        local marks = system_marks(actor)
        if in_nebula(actor) then
            return unknown_word() .. (#marks > 0 and (", " .. table.concat(marks, ", ")) or "")
        end
        -- Its hover label names it ("System 3,520.1"); four systems all
        -- read "Star system" (State of Flux, VM, 2026-10-15). A warning
        -- the game gives the system is said too.
        local name = "Star system"
        pcall(function()
            local tip = actor:GetTooltipWidgetText():ToString()
            -- The game's own word before the number ("System", "Système"):
            -- matching the English word worked only by luck in German
            -- (firefly82's review, 2026-10-19).
            -- Words may follow the number ("System 8.240.2 Krowtonanisches
            -- Zivilsystem", German, VM, 2026-10-19); spoken_number keeps them.
            local word, n = tip:match("^(%D-)%s*(%d.*)$")
            if n and word ~= "" then name = word .. " " .. M.spoken_number(n) elseif tip ~= "" then name = tip end
        end)
        pcall(function()
            local warn = actor.SystemWarning:ToString()
            -- Not when the name already says it: "Ogla Main Settlement, Ogla
            -- Main Settlement" (Q Trials, VM, 2026-10-15).
            if warn ~= "" and not name:find(warn, 1, true) then marks[#marks + 1] = warn end
        end)
        return name .. (#marks > 0 and (", " .. table.concat(marks, ", ")) or "")
    end
    if in_nebula(actor) then return unknown_word() end
    -- The game's own name, as its hover label shows it: "Class L Planet
    -- with Potential Food Sources" was read from the class as "Planet story
    -- yellow greenish eco zone planet", and ships as "Ship" where the game
    -- says "Vidiian Interceptor" (full game, VM, 2026-10-14). The class is
    -- the fallback.
    local ok, tip = pcall(function() return actor:GetTooltipWidgetText():ToString() end)
    if ok and type(tip) == "string" and tip ~= "" then return tip end
    -- tr.word: Ship
    if NAMES[cls] then return require("tr").word(NAMES[cls]) end
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
    local text = require("text")
    local function add(res)
        if seen[res] then return end
        seen[res] = true
        -- The game's own word: "Klasse-H-Planet, Food" where the detail
        -- window says "Nahrung" (firefly82's review, 2026-10-23).
        found[#found + 1] = text.game_resource_name(res) or (res:gsub("(%l)(%u)", "%1 %2"))
    end
    pcall(function()
        poi.EventIds:ForEach(function(_, e)
            local id = e:get():ToString()
            -- Every resource the id names. The number can be negative
            -- ("ResourceEvent_Generated_Duranium_-18" was said as just
            -- "scanned", German game, 2026-10-18). A combined event names
            -- two ("CombinedResourceEvent_ResourceEvent_Generated_Duranium_
            -- 388_ResourceEvent_Generated_Tritanium_318"), and the scan's
            -- detail window shows both, where the list said only the marker's
            -- one icon: "Duranium" for "Duranium; Tritanium" (firefly82's
            -- review, 2026-10-23).
            for res in id:gmatch("ResourceEvent_Generated_(%a+)_%-?%d+") do add(res) end
        end)
    end)
    return table.concat(found, require("tr").word(" and "))
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
    -- A found text that ends a sentence went before a comma: "We need to
    -- scan it to find out more., 6 cycles away" (VM, 2026-10-21).
    res = (res:gsub("%s*%.%s*$", ""))
    -- A point whose events are all over (ESTVEventState Completed 5 or
    -- Failed 7) has nothing left: arriving there again opens nothing, and a
    -- player asked how to collect at a planet (forum, 2026-10-17).
    local done = nil
    pcall(function()
        local es = FindFirstOf("STVEventSubsystem")
        if not (es and es:IsValid()) then return end
        p.poi.EventIds:ForEach(function(_, e)
            local s = es:GetEventStateById(e:get())
            if s == 5 or s == 7 then
                if done == nil then done = true end
            else
                done = false
            end
        end)
    end)
    if done then return (res ~= "" and (res .. ", ") or "") .. require("tr").word("done") end
    return res ~= "" and res or "scanned"
end

-- The player's ship on the maps: Voyager in the campaign, her Q Trials
-- class, and the Equinox (Equinox DLC, Q Trials). Only the campaign class
-- was looked for, so travel times were missing on the Equinox (VM,
-- 2026-10-19), and likely in every Q Trial.
local PLAYER_SHIPS = { "BP_SectorVoyager_C", "BP_SectorVoyager_Sandbox_C", "BP_SectorEquinox_C" }
M.PLAYER_SHIPS = PLAYER_SHIPS

local function voyager()
    for _, cls in ipairs(PLAYER_SHIPS) do
        for _, v in ipairs(FindAllOf(cls) or {}) do
            if v:IsValid() and path_of(v):find("PersistentLevel", 1, true) then return v end
        end
    end
    return nil
end

-- The trip's length in cycles, as the game shows it under the selected
-- point ("3 Zyklen entfernt", WBP_System_POI_Selection_Display.Action_Text,
-- German game, 2026-10-18); GetTimeToTravel gave the same number, and the
-- mod said nothing about it. nil where Voyager already is, and where the
-- game would not fly: her own system on the Sector Map said "Voyager is
-- here, 3 cycles away", the way to its centre (CanTravel false, 2026-10-18).
local function travel_time(p)
    local n = nil
    pcall(function()
        local j = FindFirstOf("STVJourneySubsystem")
        local ship = voyager()
        if not (j and j:IsValid() and ship) then return end
        if j:CanTravel(ship, p.poi, {}) == false then return end
        n = j:GetTimeToTravel(ship, p.actor, {}, {})
    end)
    if type(n) ~= "number" or n <= 0 then return nil end
    return n .. (n == 1 and " cycle away" or " cycles away")
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
                if not cls:find("^BP_SectorVoyager") and cls ~= "BP_SectorEquinox_C" and want then
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
    local travel = travel_time(p)
    local text = string.format("%s, %s%s, %s%d of %d", name, status(p), inside_text(p.actor), travel and (travel .. ", ") or "", i, #list)
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
    -- The inspect view has nothing to move through (M.inspect_view).
    if M.inspect_view() then return speech.say("Backspace goes back.", true) end
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
    if M.inspect_view() then return speech.say("Backspace goes back.", true) end
    local list = points()
    if #list == 0 then return end
    select(list, last and #list or 1)
end

-- Enter on a point opens a short list of actions (Casey: lists move with
-- Up and Down, 2026-10-10). Scan is proven (it revealed Deuterium,
-- 2026-10-10). Set course puts the camera on the point, as gamepad hovering
-- does, then fires the set-course input's own handlers: proven 2026-10-11,
-- Voyager moved toward the selected Class P planet.
-- Inspect is the panel's third button (InspectPOIButton, firefly82's review
-- 6.3), listed when the game shows it for the selected point; its name is
-- the game's own button text.
local BASE_ACTIONS = { "Scan", "Set course" }
local ACTIONS = BASE_ACTIONS
local inspect_label = nil

local function item_name(a)
    if a == "Inspect" then return inspect_label or a end
    -- tr.word: Scan
    return require("tr").word(a)
end

function M.menu_open()
    return menu ~= nil
end

local function selected_point()
    local list = points()
    local i = index_of_selected(list)
    return i and list[i] or nil
end

-- Set course sometimes did nothing (Casey, 2026-10-11): set course is a
-- hold-to-charge input, and the mod fired it in one go. It is held now
-- (set_course below); the game has a silent travel error
-- (STVUserError_CanTravelSilent) next to the ones it shows as toasts, so a
-- course that does not start is still said.

-- Travel the way the game does it (outside review, 24 October 2026).
-- The course is set as a player sets it: the pointer on the point (as in the
-- ship view) and the game's own Set course input, IA_Sector_SetCourse,
-- held; it takes a hold of 0.6 s (InputTriggerHold, one shot). The game
-- then takes the point under the pointer, fills PoiSelectedForTravel itself
-- and flies (probe r2, 24 October: with the pointer elsewhere it did
-- nothing at all). What is said comes from the game: the ship starting to
-- move (STVSectorPawn:OnShipMovementStarted), the journey's share of the
-- trip (OnTravelProgress) and its end (OnTravelCompleted). No
-- DeclareTravel, no distances, no second try behind the player's back.
-- OnTravelCompleted's flag is no sign of an event: the point's event came
-- with it false at five points in a row (24 October).
local trip = nil      -- { name, path, progress, half }: the trip under way
local pending = nil   -- { name, path }: a course the mod is setting now
local waiting = nil   -- { name, path, busy, token }: after an arrival
local set_course      -- below run(), which calls it

local function busy_now()
    for _, w in ipairs(require("popups").open_windows()) do
        -- Map markers and room prompts are windows too and always up; a
        -- point's detail panel holds nothing back either.
        if not w:find("WBP_PoiEventWidget_C", 1, true) and not w:find("RoomPrompt", 1, true)
            and not w:find("DetailView", 1, true) then return true end
    end
    return require("dialogue").active() and true or false
end

-- Whether the point at path has an event in ESTVEventState state (3
-- Activatable: waiting; 4 Active and 6 AwaitingConfirmation: open now).
local function event_in_state(path, state)
    local a = StaticFindObject(path)
    if not (a and a:IsValid()) then return false end
    local c = poi_of(a)
    local es = FindFirstOf("STVEventSubsystem")
    if not (c and es and es:IsValid()) then return false end
    local yes = false
    c.EventIds:ForEach(function(_, e)
        if es:GetEventStateById(e:get()) == state then yes = true end
    end)
    return yes
end
local function event_waiting(path) return event_in_state(path, 3) end
-- An arrival conversation ("Orders?" with Return later) holds its event in
-- 6, AwaitingConfirmation, not 4 (VM probe, Class L planet, 2026-10-27).
local function event_open(path) return event_in_state(path, 6) or event_in_state(path, 4) end

-- After an arrival the point's event can be left waiting. The game holds it
-- back while a report is up and opens it when the report closes (energy
-- loss reports at the Kazon hunter and the Vidiian interceptor, a
-- construction report at a Class G planet, 24 October), but not when a
-- second message follows the report or a decision is up (Talaxian freighter
-- and Class L planet, 23 October; Class E planet twice, 24 October); there,
-- as for a sighted player, only a trip away and back starts it. Looked at
-- when the game says something changed (a window read or closed, a
-- transition finished), not in a loop; each look waits 1.5 s once,
-- because the game opens a held-back event within that second.
local function look_waiting()
    local w = waiting
    if not w then return end
    w.token = w.token + 1
    local mine = w.token
    ExecuteInGameThreadWithDelay(1500, function()
        if waiting ~= w or w.token ~= mine then return end
        pcall(function()
            if busy_now() then
                w.busy = true
                -- The point's own event open (its arrival conversation): it
                -- did start. "Return later" puts it back to waiting, and that
                -- was said as "did not start" (Ocampa, Casey, 2026-10-27).
                if not w.opened and event_open(w.path) then
                    w.opened = true
                    print("[VoyagerAccess] course: the event at " .. w.name .. " is open\n")
                end
                return
            end
            waiting = nil
            -- Only after a window that was really up: Friendship One's Class O
            -- planet keeps a waiting event that its scan starts (VM,
            -- 2026-10-21).
            if w.opened or not (w.busy and event_waiting(w.path)) then return end
            print("[VoyagerAccess] course: event waiting at " .. w.name .. " did not open\n")
            speech.say("The event at " .. w.name .. " did not start. Set course to another point and back to start it.", false)
        end)
    end)
end

-- Enter on a conversation choice (focus.lua), before the game takes it:
-- an arrival conversation answered within the look's 1.5 s (Return later)
-- would otherwise be seen only after, back in state 3 (Fable review).
function M.before_choice()
    local w = waiting
    if not w or w.opened then return end
    if event_open(w.path) then
        w.opened = true
        print("[VoyagerAccess] course: the event at " .. w.name .. " is open (choice)\n")
    end
end

local function battle_up()
    local ok, up = pcall(function() return require("combat").screen_up() end)
    return ok and up and true or false
end

-- The ship has started to move. Its target from the game; the mod's own
-- name for it when the mod set the course.
local holding = nil   -- the running Set course hold, { stop = function } (hold_set_course)
local function on_started()
    -- Only the mod's own course (pending): a move the game starts by itself
    -- must not cut a hold short of the game's 0.6 s (Fable review).
    if holding and pending then holding.stop("the trip started") end
    local name, path = nil, nil
    if pending then name, path = pending.name, pending.path end
    pcall(function()
        local pw = pawn()
        local t = pw and pw.PoiSelectedForTravel
        if t and t:IsValid() then
            local a = t:GetOwner()
            if a and a:IsValid() and path_of(a) ~= path then path, name = path_of(a), name_of(a) end
        end
    end)
    pending, waiting = nil, nil
    if not name then return end
    trip = { name = name, path = path, progress = 0, half = false }
    print("[VoyagerAccess] course: under way to " .. name .. "\n")
    if not battle_up() then speech.say("Under way to " .. name, false) end
end

local function on_progress(share)
    local t = trip
    if not t then return end
    t.progress = share
    if t.half or share < 0.5 then return end
    t.half = true
    if not battle_up() then speech.say("Halfway to " .. t.name, false) end
end

-- The trip has ended. A point's event, a report or an arrival
-- conversation can come right after; each is read when it comes and cuts
-- this line off.
local function on_completed()
    local t = trip
    trip = nil
    if not t then return end
    local battle = battle_up()
    print("[VoyagerAccess] course: arrived at " .. t.name .. (battle and " (in battle, not said)" or "") .. "\n")
    if battle then return end
    speech.say("Arrived at " .. t.name, false)
    waiting = { name = t.name, path = t.path, busy = false, token = 0 }
    look_waiting()
end

-- Installed once (M.install). Hooks on the journey's and the pawn's native
-- functions; probe r1 saw all of them fire on every trip (24 October).
function M.hook_travel()
    if M.travel_hooked then return end
    M.travel_hooked = true
    local P = "/Script/STVoyager.STVSectorPawn:"
    local J = "/Script/STVoyager.STVJourneySubsystem:"
    local ok1 = pcall(RegisterHook, P .. "OnShipMovementStarted", function()
        ExecuteInGameThread(function() pcall(on_started) end)
    end)
    local ok2 = pcall(RegisterHook, J .. "OnTravelProgress", function(_, p)
        local share = nil
        pcall(function() share = p:get() end)
        -- Every frame of a trip: only a number stored, said once at half.
        if type(share) == "number" and trip and not trip.half and share >= 0.5 then
            ExecuteInGameThread(function() pcall(on_progress, share) end)
        elseif type(share) == "number" and trip then
            trip.progress = share
        end
    end)
    local ok3 = pcall(RegisterHook, J .. "OnTravelCompleted", function()
        ExecuteInGameThread(function() pcall(on_completed) end)
    end)
    local ok4 = pcall(RegisterHook, J .. "OnStateTransitionFinished", function()
        ExecuteInGameThread(function() pcall(look_waiting) end)
    end)
    -- The event bus's arrival at a point (firefly82's census, 26 October),
    -- logged only, against OnTravelCompleted: ending the waiting-event
    -- watch on it would drop a window that opens after it.
    local ok5 = pcall(RegisterHook, "/Script/STVoyager.STVSectorSummarySubsystem:OnArrivedAtPOI", function()
        ExecuteInGameThread(function() print("[VoyagerAccess] course: arrived at a point (event bus)\n") end)
    end)
    print("[VoyagerAccess] course: arrival event " .. (ok5 and "hooked" or "not hooked") .. "\n")
    local popups = require("popups")
    -- A point's detail panel and its parts (WBP_POIDetailView_C,
    -- WBP_PlanetDetailView_C, ...) are no window that holds an event back.
    popups.on_read(function(_, cls)
        if waiting and not tostring(cls):find("DetailView", 1, true) then
            waiting.busy = true
            local ok, open = pcall(event_open, waiting.path)
            if ok and open and not waiting.opened then
                waiting.opened = true
                print("[VoyagerAccess] course: the event at " .. waiting.name .. " is open\n")
            end
        end
    end)
    popups.on_close(function() pcall(look_waiting) end)
    print(string.format("[VoyagerAccess] course: travel hooks %s %s %s %s\n", tostring(ok1), tostring(ok2), tostring(ok3), tostring(ok4)))
end

-- For L: "Traveling to Class E planet, 40 percent of the way", or nil. The
-- share is the game's own (OnTravelProgress).
function M.travel_status()
    local t = trip
    if not t then return nil end
    local pct = math.floor((t.progress or 0) * 100 + 0.5)
    return "Traveling to " .. t.name .. string.format(", %d percent of the way", math.max(0, math.min(100, pct)))
end

-- The path of the point the player's ship is at, "" while travelling, nil
-- when the ship cannot say (then the game decides when the course is set).
local function ship_at_point()
    local out = nil
    pcall(function()
        local j = FindFirstOf("STVJourneySubsystem")
        if j and j:IsValid() and j:IsTravelling() then out = "" return end
        for _, cls in ipairs(PLAYER_SHIPS) do
            for _, s in ipairs(FindAllOf(cls) or {}) do
                if s:IsValid() and not s:GetFullName():find("Default__", 1, true) then
                    local poi = s.CurrentPOI
                    if poi and poi:IsValid() then
                        local owner = poi:GetOwner()
                        if owner and owner:IsValid() then out = path_of(owner) end
                    end
                    return
                end
            end
        end
    end)
    return out
end

-- "Voyager is already at X", and when X has a story waiting, how to start
-- it: the game starts a point's story only on arrival, so a story that
-- became ready while Voyager was there (Sobras, the Kazon Raider, VM,
-- 2026-10-16) waited for a trip away and back.
local function already_at(name, actor)
    local text = "Voyager is already at " .. name
    pcall(function()
        if type(actor) == "string" then actor = StaticFindObject(actor) end
        local marks = (actor and actor:IsValid()) and system_marks(actor) or {}
        if table.concat(marks, ","):find("mission", 1, true) then
            text = text .. ". Its story starts when Voyager arrives: set course to another point, then back here"
        end
    end)
    return text
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
        -- Why a scan is refused: the game builds its message from the
        -- missing scanner tags (Ability.Scan.CanScan when Stellar
        -- Cartography is damaged or off; "The scan did not finish" was all
        -- the mod said, sector 5, VM, 2026-10-16). Hooked once per load,
        -- after the pawn's class exists.
        M.scan_missing = nil
        if not M.scan_hooked then
            M.scan_hooked = pcall(RegisterHook,
                "/Game/STVoyager/JourneyGenerator/Blueprints/BP_SectorPawn.BP_SectorPawn_C:GenerateScannerErrorMessage",
                function(_, tags)
                    local out = {}
                    pcall(function()
                        tags:get().GameplayTags:ForEach(function(_, t) out[#out + 1] = t:get().TagName:ToString() end)
                    end)
                    M.scan_missing = out
                end)
        end
        local forgotten = require("popups").reread_for("POIDetailView")
        local before = found[p.path]
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
                    if res == "" then
                        -- The panel read again after the scan has said it:
                        -- "Found Spatial Anomaly, Our sensors..." repeated the
                        -- panel's whole text 0.7 s later (Casey, 2026-10-26).
                        if found[q.path] and found[q.path] ~= before then return end
                        res = found[q.path] or ""
                    end
                    -- The full game's event IDs are not ResourceEvent_Generated_*,
                    -- so "nothing found" followed a panel listing Tritanium
                    -- (Q Trial, VM, 2026-10-14); the panel says what was found.
                    speech.say(res ~= "" and ("Found " .. res) or "Scan complete", false)
                else
                    -- Nothing new to read: the details are remembered again.
                    pcall(require("popups").restore, forgotten)
                    local why = ""
                    for _, t in ipairs(M.scan_missing or {}) do
                        if t:find("CanScan", 1, true) then why = ": the scanner needs a working Stellar Cartography"
                        elseif t:find("Forbid", 1, true) then why = ": a Q Trials rule forbids scanning here" end
                    end
                    speech.say("The scan did not finish" .. why, false)
                end
            end)
        end)
    else
        -- The ship says where it is: its CurrentPOI, while not travelling
        -- (firefly82's probe, 2026-10-23). Otherwise the game decides; a
        -- course it does not take is said below.
        local here = ship_at_point()
        if here and here ~= "" and here == p.path then
            print("[VoyagerAccess] course: already at (the ship's CurrentPOI)\n")
            speech.say(already_at(name, p.actor), true)
            return
        end
        speech.say("Setting course for " .. name, true)
        set_course(name, p.path)
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
        for _, cls in ipairs(PLAYER_SHIPS) do
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

-- What the game's own pointer is over now, against the point the mod aimed
-- at: "target", "nothing", "other <name>", "no cursor widget" or "error ...".
-- The game's cursor (WBP_CustomCursor_C, USTVCustomCursor) has no event
-- for it, but GetHoveredActor answers (firefly82's probe, 2026-10-26).
-- Logged at every hold and select, so a course the game did not take says
-- whether the pointer was on the point (five holds not taken for the
-- Shipwreck beside the Array, Casey, 2026-10-26).
local function under_pointer(path)
    local r = "no cursor widget"
    local ok, err = pcall(function()
        -- The shown one, if the game keeps more than one (Fable review).
        local c, shown = nil, false
        for _, x in ipairs(FindAllOf("WBP_CustomCursor_C") or {}) do
            if x:IsValid() and not x:GetFullName():find("Default__", 1, true) and not shown then
                shown = require("screen").shown(x) and true or false
                c = x
            end
        end
        if not c then return end
        -- None shown: said so, so the line is not taken for the real pointer
        -- (GPT review, 2026-10-26).
        local tag = shown and "" or " (hidden cursor)"
        local a = c:GetHoveredActor()
        if not (a and a:IsValid()) then r = "nothing" .. tag return end
        local p = path_of(a)
        if p == path then r = "target" .. tag return end
        -- The point's own parts (a component's actor) count as the point.
        local okw, owner = pcall(function() return a:GetOwner() end)
        if okw and owner and owner:IsValid() and path_of(owner) == path then r = "target" .. tag return end
        r = "other " .. a:GetFName():ToString() .. tag
    end)
    if not ok then r = "error " .. tostring(err) end
    return r
end
M.under_pointer = under_pointer

-- The game's Set course input held, as a player holds the mouse button or
-- the gamepad's A on the point: injected every 20 ms for 0.8 s (the game
-- wants 0.6 s), then ended by its handle and, as a second guard, by a step
-- count (a loop without its handle ran on, probe 2026-10-20).
local SET_COURSE = nil
-- Injected on every game tick (a 1 ms loop runs once a tick), for 1 s: the
-- game's hold trigger counts held time from tick to tick, and a 20 ms loop
-- sent 10 injections over 0.8 s in the VM's low frame rate, so a tick
-- without one could reset the hold; the game took no course on about 2 of
-- 5 tries in the demo (2026-10-24).
local HOLD_MS, STEP_MS = 1000, 1
-- The running hold, ended early by the game's own start event (on_started):
-- the game takes a course at its 0.6 s (IA_Sector_SetCourse's
-- HoldTimeThreshold), and in firefly82's five courses (26 October) the
-- trip started 0.4 s before the hold ended, so 0.4 s of input ran on into
-- the trip. HOLD_MS stays as the bound for a course the game does not take.
-- (holding is declared before on_started, which ends it.)
local function hold_set_course()
    local sub = nil
    for _, s in ipairs(FindAllOf("EnhancedInputLocalPlayerSubsystem") or {}) do
        if s:IsValid() and path_of(s):find("^/Engine/Transient%.") then sub = s end
    end
    if not (SET_COURSE and SET_COURSE:IsValid()) then
        SET_COURSE = nil
        for _, ctx in ipairs(FindAllOf("InputMappingContext") or {}) do
            if ctx:IsValid() and not ctx:GetFullName():find("Default__", 1, true) then
                pcall(function()
                    ctx.Mappings:ForEach(function(_, e)
                        local a = e:get().Action
                        if a and a:IsValid() and a:GetFName():ToString() == "IA_Sector_SetCourse" then SET_COURSE = a end
                    end)
                end)
            end
        end
    end
    if not (sub and SET_COURSE) then
        print("[VoyagerAccess] course: no Set course input to hold\n")
        return false
    end
    if holding then holding.stop("replaced") end
    local action, n, sent, handle = SET_COURSE, 0, 0, nil
    local started = os.clock()
    local mine = {}
    handle = LoopInGameThreadWithDelay(STEP_MS, function()
        n = n + 1
        -- Stopped (by the trip, a new course or the bound) sends nothing
        -- more even if the cancel did not take (GPT review, 2026-10-26).
        if mine.stopped or os.clock() - started > (HOLD_MS + 200) / 1000 or n > 400 then
            pcall(CancelDelayedAction, handle)
            return
        end
        local ok = pcall(function() sub:InjectInputVectorForAction(action, { X = 1.0, Y = 0.0, Z = 0.0 }, {}, {}) end)
        if ok then sent = sent + 1 end
    end)
    function mine.stop(why)
        if mine.stopped then return end
        mine.stopped = true
        if holding == mine then holding = nil end
        pcall(CancelDelayedAction, handle)
        print(string.format("[VoyagerAccess] course: Set course held %d ms (%s), %d of %d steps sent\n",
            math.floor((os.clock() - started) * 1000), why, sent, n))
    end
    holding = mine
    ExecuteInGameThreadWithDelay(HOLD_MS, function() mine.stop("full hold") end)
    return true
end

-- The camera to the point (SetFocusPoint, as before), the pointer on it,
-- then the hold. The camera glides for about 0.9 s and the map has no event
-- for its end, so the pointer follows after that time. After a story scene
-- the camera is held on Voyager (bForceFollow) and the point can be off
-- screen: a sighted player zooms out, so does the mod (Sikaris, State of
-- Flux, VM, 2026-10-15).
-- Only the newest course request goes on through its delayed steps: a
-- second point chosen within those 1.6 s would otherwise have both holds
-- run, and the ship could take the first (GPT review, 2026-10-24).
local course_token = 0
-- STVJourneySubsystem:DeclareTravel(ship, point) flies Voyager with the
-- trip's usual events (OnShipMovementStarted says "Under way" from pending)
-- and leaves the pawn's PoiSelectedForTravel empty. True when the call was
-- made; "not set" is said if Voyager is not travelling 1.5 s later.
local function declare_travel(name, path)
    local ok, made = pcall(function()
        local j = FindFirstOf("STVJourneySubsystem")
        local ship = voyager()
        local poi = nil
        for _, c in ipairs(FindAllOf("STVPointOfInterestBase") or {}) do
            if c:IsValid() and path_of(c):find("PersistentLevel", 1, true) then
                local a = c:GetOwner()
                if a and a:IsValid() and path_of(a) == path then poi = c end
            end
        end
        if not (j and j:IsValid() and ship and poi) then return false end
        if not j:CanTravel(ship, poi, {}) then return false end
        pending = { name = name, path = path }
        print("[VoyagerAccess] course: DeclareTravel " .. name .. "\n")
        j:DeclareTravel(ship, poi)
        return true
    end)
    if not (ok and made) then
        pending = nil
        print("[VoyagerAccess] course: DeclareTravel not possible (" .. tostring(made) .. ")\n")
        return false
    end
    ExecuteInGameThreadWithDelay(1500, function()
        if not (pending and pending.path == path) then return end
        local moving = false
        pcall(function()
            local j = FindFirstOf("STVJourneySubsystem")
            moving = j and j:IsValid() and j:IsTravelling() and true or false
        end)
        if moving then return on_started() end
        pending = nil
        print("[VoyagerAccess] course: DeclareTravel did not move\n")
        speech.say("The course for " .. name .. " was not set. Press Enter and choose Set course again.", false)
    end)
    return true
end
set_course = function(name, path, zooms, tok, again)
    zooms = zooms or 0
    if not tok then
        course_token = course_token + 1
        tok = course_token
        -- A new destination: the old one's hold stops now, not at its bound
        -- (GPT review, 2026-10-26).
        if holding then holding.stop("new course") end
    end
    local function stale() return tok ~= course_token end
    waiting = nil
    local q0 = pawn()
    local a0 = StaticFindObject(path)
    if not (q0 and a0 and a0:IsValid()) then return end
    if zooms == 0 then pcall(function() q0:SetFocusPoint(a0) end) end
    ExecuteInGameThreadWithDelay(zooms == 0 and 900 or 600, function()
        if stale() then return end
        pcall(function()
            local q = pawn()
            local a = StaticFindObject(path)
            if not (q and a and a:IsValid()) then return end
            if zooms < 3 and on_screen(a) == false then
                local okz = pcall(function() q.TargetZoom = math.min((q.TargetZoom or 30000) * 2, 250000) end)
                if okz then
                    print("[VoyagerAccess] course: zooming out, target off screen\n")
                    set_course(name, path, zooms + 1, tok, again)
                    return
                end
            end
            aim_at(a, false)
            -- The helper puts the pointer there within about 50 ms; the
            -- game takes the course only with some time between the
            -- pointer and the hold (0.15 s failed twice, 0.7 s worked in
            -- probes r2 and c2, 24 October).
            ExecuteInGameThreadWithDelay(700, function()
                if stale() then return end
                pending = { name = name, path = path }
                local under = under_pointer(path)
                pending.under = under
                print("[VoyagerAccess] course: under the pointer at the hold: " .. under .. "\n")
                if not hold_set_course() then
                    pending = nil
                    if declare_travel(name, path) then return end
                    speech.say("The course for " .. name .. " was not set. Press Enter and choose Set course again.", false)
                    return
                end
                -- The ship starts within a second of the hold (probe r2). A
                -- course the game did not take: when it gives a reason it
                -- shows it as a message, which is read; the mod adds only
                -- that nothing started, and nothing over a window.
                ExecuteInGameThreadWithDelay(HOLD_MS + 1500, function()
                    -- A newer request (the same point chosen again) owns
                    -- pending now: this one says nothing (Fable review,
                    -- 2026-10-26: "not set" came while the second hold ran).
                    if stale() then return end
                    if not (pending and pending.path == path) then return end
                    -- Moving with no start event (its hook did not register
                    -- after a game patch): the trip is said from here, not
                    -- "not set" while Voyager flies (Fable review, 2026-10-24).
                    local moving = false
                    pcall(function()
                        local j = FindFirstOf("STVJourneySubsystem")
                        moving = j and j:IsValid() and j:IsTravelling() and true or false
                    end)
                    if moving then
                        print("[VoyagerAccess] course: travelling with no start event\n")
                        return on_started()
                    end
                    print("[VoyagerAccess] course: the game took no course for " .. name .. (again and ", second hold" or "")
                        .. " (pointer at the hold: " .. tostring(pending.under) .. ", now: " .. under_pointer(path) .. ")\n")
                    pending = nil
                    local busy = false
                    pcall(function() busy = busy_now() end)
                    -- One more aim and hold before the player hears it failed:
                    -- the game sometimes took no course from a hold with the
                    -- pointer on the point (demo, 1 of 2 tries; full game, 3
                    -- tries in one session) and took the same course when
                    -- asked again (VM, 2026-10-24). There is no game signal
                    -- for "the point is under the pointer" to wait for.
                    if not busy and not again and not stale() then
                        return set_course(name, path, 3, tok, true)
                    end
                    -- The last fallback, when both holds were not taken:
                    -- the journey's own DeclareTravel, only when its
                    -- CanTravel agrees. Five holds in a row were not taken
                    -- for the Shipwreck beside the Array (Casey's machine,
                    -- sector 1, 2026-10-26); 0.3.81 and before had this
                    -- step (forum player whose game never took the pointer).
                    if not busy and not stale() and declare_travel(name, path) then return end
                    if not busy then
                        speech.say("The course for " .. name .. " was not set. Press Enter and choose Set course again.", false)
                    end
                end)
            end)
        end)
    end)
end

-- One of the game's map inputs by name (IA_Sector_SelectPoi, ...), and the
-- player's input subsystem, or nil.
local ACTION_CACHE = {}
local function input_action(name)
    local sub = nil
    for _, s in ipairs(FindAllOf("EnhancedInputLocalPlayerSubsystem") or {}) do
        if s:IsValid() and path_of(s):find("^/Engine/Transient%.") then sub = s end
    end
    local a = ACTION_CACHE[name]
    if not (a and a:IsValid()) then
        a = nil
        for _, ctx in ipairs(FindAllOf("InputMappingContext") or {}) do
            if ctx:IsValid() and not ctx:GetFullName():find("Default__", 1, true) then
                pcall(function()
                    ctx.Mappings:ForEach(function(_, e)
                        local x = e:get().Action
                        if x and x:IsValid() and x:GetFName():ToString() == name then a = x end
                    end)
                end)
            end
        end
        ACTION_CACHE[name] = a
    end
    if not (sub and a) then return nil end
    return a, sub
end

-- One press of a game input that takes a tap (not a hold).
local function tap(name)
    local a, sub = input_action(name)
    if not a then return false end
    return pcall(function() sub:InjectInputVectorForAction(a, { X = 1.0, Y = 0.0, Z = 0.0 }, {}, {}) end)
end

-- Enter on a point selects it in the game first, as a click on it does
-- (firefly82's probe a1, 24 October: the pointer on the point and the
-- game's IA_Sector_SelectPoi once filled SelectedActor and opened the
-- game's own detail panel, WBP_POIDetailView, with name, system, zone,
-- resources and the Stellar Cartography hint). The mod's list never
-- selected, so that panel was heard only once, at the scan; a sighted
-- player sees it on every click. Not on every arrow: that would move the
-- real pointer and read a panel on each key. The System Map only: the
-- Sector Map has no select input (IMC_Sector_Map). The action list follows
-- the panel; if no panel is read within 2 s, it opens anyway.
local selecting = nil   -- { path, done, tapped }: a selection under way
local function select_in_game(p, done)
    if not context_active("IMC_System_Map") then return false end
    local busy = true
    pcall(function() busy = busy_now() end)
    if busy then return false end
    if not input_action("IA_Sector_SelectPoi") then return false end
    local path = p.path
    -- The panel may say the same as when it was last read (the same point
    -- again): forgotten so that it is read, put back if nothing came.
    local forgotten = require("popups").forget("POIDetailView")
    local job = { path = path, done = done }
    selecting = job
    local function stale()
        return selecting ~= job or selected ~= path or menu == nil
    end
    local function give_up()
        if selecting == job then selecting = nil end
        pcall(require("popups").restore, forgotten)
    end
    -- The camera glides to a point for about 0.9 s after an arrow
    -- (SetFocusPoint in select); the pointer goes on the point after that.
    local wait = math.max(0, 900 - math.floor((os.clock() - M.last_move) * 1000))
    if on_screen(p.actor) == false then
        local pw = pawn()
        if pw then pcall(function() pw:SetFocusPoint(p.actor) end) end
        wait = 900
    end
    ExecuteInGameThreadWithDelay(math.max(wait, 10), function()
        if stale() then return give_up() end
        local a = StaticFindObject(path)
        if not (a and a:IsValid()) then give_up() return done(false) end
        aim_at(a, false)
        -- Time between the pointer and the input, as for set course (0.6 s
        -- in probes a1 and r3b).
        ExecuteInGameThreadWithDelay(600, function()
            if stale() then return give_up() end
            local under = under_pointer(path)
            local ok = tap("IA_Sector_SelectPoi")
            print("[VoyagerAccess] system: select in game " .. tostring(ok) .. ", under the pointer: " .. under .. "\n")
            if not ok then give_up() return done(false) end
            job.tapped = true
            ExecuteInGameThreadWithDelay(2000, function()
                if selecting ~= job then return end
                print("[VoyagerAccess] system: no detail panel read after the selection\n")
                -- Asked before give_up, which clears the job and so would
                -- make stale() true (GPT review, 2026-10-24).
                local still = not stale()
                give_up()
                if still then done(false) end
            end)
        end)
    end)
    return true
end

-- The game's detail panel was read (popups.on_read, M.install).
local function on_panel_read()
    local job = selecting
    -- Only a read after the input: the panel of the point before could be
    -- read again while the pointer moves.
    if not (job and job.tapped) then return end
    selecting = nil
    if selected == job.path and menu ~= nil then job.done(true) end
end
M.on_panel_read = on_panel_read

-- The game's Inspect button and its text, when the panel shows it shown and
-- enabled for the point at path, the one the game has selected; else nil.
local function inspect_button(path)
    local out, label = nil, nil
    pcall(function()
        local pw = pawn()
        local sel = pw and pw.SelectedActor
        if not (sel and sel:IsValid() and path_of(sel) == path) then return end
        local screen = require("screen")
        for _, v in ipairs(FindAllOf("STVPOIDetailActionView") or {}) do
            if v:IsValid() and path_of(v):find("^/Engine/Transient%.") and screen.shown(v) then
                local b = v.InspectPOIButton
                if b and b:IsValid() and screen.shown(b) and b:GetIsEnabled() then
                    local t = ""
                    pcall(function() t = require("popups").plain(b.ButtonText:GetText():ToString()) end)
                    if t ~= "" then out, label = b, t end
                end
            end
        end
    end)
    return out, label
end

local list_said = false   -- whether the open action list has said an item
local function open_list(after_panel)
    if menu == nil then return end
    -- The panel's buttons as the game shows them now.
    local p = selected_point()
    local b, label = nil, nil
    if p then b, label = inspect_button(p.path) end
    if b then
        ACTIONS, inspect_label = { BASE_ACTIONS[1], BASE_ACTIONS[2], "Inspect" }, label
    else
        ACTIONS = BASE_ACTIONS
        if menu > #ACTIONS then menu = #ACTIONS end
    end
    if list_said then return end
    list_said = true
    -- After the panel, queued behind it; otherwise at once. "Menu" first:
    -- Enter on a point gave no sign that a list had opened (Casey,
    -- 2026-10-26); the game shows its buttons beside the panel.
    speech.say(require("tr").word("Menu") .. ". " .. item_name(ACTIONS[1]) .. ", 1 of " .. #ACTIONS, not after_panel)
end

-- Inspect opens the game's close view of the point (PoiViewPawn, input
-- IMC_PoiView_Map: turn with the mouse or the right stick, zoom with the
-- wheel, leave with the right mouse button or the gamepad's B; no keyboard
-- key). Nothing there is text, so the mod says how to leave it, and
-- Backspace leaves it with the game's own IA_PoiView_Cancel.
function M.inspect_view()
    return context_active("IMC_PoiView_Map")
end

local function inspect(p)
    local b, label = inspect_button(p.path)
    if not b then
        speech.say(require("tr").fill("Not available: {s}", inspect_label or "Inspect"), true)
        return
    end
    print("[VoyagerAccess] system: inspect " .. name_of(p.actor) .. "\n")
    speech.say(label, true)
    -- Pressed, released and clicked, as focus.lua clicks a button.
    local ok = pcall(function()
        b:HandleButtonPressed()
        b:HandleButtonReleased()
        b:HandleButtonClicked()
    end)
    if not ok then return end
    ExecuteInGameThreadWithDelay(1500, function()
        pcall(function()
            if M.inspect_view() then
                speech.say("Backspace goes back.", false)
            else
                print("[VoyagerAccess] system: no inspect view after the button\n")
            end
        end)
    end)
end

-- Backspace in the inspect view (focus.lua): the game's cancel input.
function M.inspect_close()
    local ok, up = pcall(M.inspect_view)
    if not (ok and up) then return false end
    if not tap("IA_PoiView_Cancel") then return false end
    ExecuteInGameThreadWithDelay(700, function()
        pcall(function()
            if M.inspect_view() then
                print("[VoyagerAccess] system: inspect view still open after cancel\n")
            else
                speech.say("Closed", true)
            end
        end)
    end)
    return true
end

function M.enter()
    crumb.at("system: enter")
    if M.inspect_view() then return speech.say("Backspace goes back.", true) end
    local p = selected_point()
    if not p then
        speech.say("Nothing selected." .. require("hints").text("map_updown", " Use Up and Down Arrow to choose a point of interest."), true)
        return
    end
    if not menu then
        menu = 1
        list_said = false
        ACTIONS = BASE_ACTIONS
        if not select_in_game(p, open_list) then open_list(false) end
        return
    end
    local action = ACTIONS[menu]
    menu = nil
    if action == "Inspect" then return inspect(p) end
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
    local travel = travel_time(p)
    local text = string.format("%s, %s%s, %s%d of %d", name, status(p), inside_text(p.actor), travel and (travel .. ", ") or "", i, #list)
    if menu then text = text .. ". Action list open: " .. item_name(ACTIONS[menu]) end
    return text
end

-- Up and Down inside the action list.
function M.menu_step(dir)
    local i = menu + dir
    list_said = true
    if not ACTIONS[i] then return end
    menu = i
    speech.say(item_name(ACTIONS[i]) .. ", " .. i .. " of " .. #ACTIONS, true)
end

function M.menu_edge(last)
    list_said = true
    menu = last and #ACTIONS or 1
    speech.say(item_name(ACTIONS[menu]) .. ", " .. menu .. " of " .. #ACTIONS, true)
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
