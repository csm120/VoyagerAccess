-- Building a room (2026-10-14). The construction ring's room choices
-- (STVRadialCommand_ConstructRoom: RoomType, Width) send the game into a
-- construction view where a sighted player clicks a slot; a slot only turns
-- green where the room fits, and nothing told a blind player that. Every
-- crew room is 2 spaces wide, and the only empty space on Deck 2 was 1 wide
-- (a damaged room beside it), so nothing could be placed and no reason was
-- given.
--
-- Room slots are STVRoomHull actors with BP_GetSlotIndex(); a hull covers
-- GridSize.X slots, numbered left to right along a deck. Empty building
-- space is room type 0 ("None"), one slot per hull; clearing a ruined room
-- leaves two of them side by side. STVConstructionManager.ConfirmBuild(Slot,
-- RoomTypeToBuild) starts the build (work team, cycles and cost taken as
-- the game's own build does; tried at slot 222: "building, 6 cycles",
-- Duranium 100 to 75).
--
-- So the mod checks the fit when a room is read in the ring, and Enter
-- builds it straight away at the selected space.

local speech = require("speech")

local M = {}

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

-- The room choice behind a ring button, or nil.
function M.command_of(b)
    local ok, cmd = pcall(function() return b.Command end)
    if not (ok and cmd and cmd:IsValid()) then return nil end
    if cmd:GetClass():GetFName():ToString() ~= "STVRadialCommand_ConstructRoom" then return nil end
    return cmd
end

-- Hulls on the selected hull's deck, by slot.
local function deck_slots(hull)
    local z = hull:K2_GetActorLocation().Z
    local by = {}
    for _, h in ipairs(FindAllOf("STVRoomHull") or {}) do
        if h:IsValid() and path_of(h):find("PersistentLevel", 1, true) then
            local loc = h:K2_GetActorLocation()
            if math.abs(loc.Z - z) < 50 then by[h:BP_GetSlotIndex()] = h end
        end
    end
    return by
end

local function empty(h)
    return h ~= nil and h:GetRoomType() == 0
end

-- Where a room of this width fits around the selected space: the first slot
-- of a run of empty spaces that includes it, and how many empty spaces in a
-- row there are there.
function M.fit(hull, width)
    local by = deck_slots(hull)
    local s = hull:BP_GetSlotIndex()
    local first, last = s, s
    while empty(by[first - 1]) do first = first - 1 end
    while empty(by[last + 1]) do last = last + 1 end
    local run = last - first + 1
    if run < width then return nil, run end
    -- Start at the selected space when the room fits from there, otherwise
    -- as far right as it can start and still cover it.
    local start = math.min(s, last - width + 1)
    return start, run
end

local function spaces(n)
    return n .. (n == 1 and " space" or " spaces")
end

-- Added to a room choice's reading: its width and whether it fits.
function M.fit_text(b)
    local cmd = M.command_of(b)
    if not cmd then return nil end
    local hull = require("ship").selected_hull()
    if not (hull and hull:IsValid() and empty(hull)) then return nil end
    local width = cmd.Width or 1
    local start, run = M.fit(hull, width)
    if start then return spaces(width) .. " wide, fits here" end
    return spaces(width) .. " wide, does not fit: " .. (run == 1 and "this empty space is 1 wide"
        or ("only " .. run .. " empty spaces side by side here")) .. ". Clear ruined rooms beside it for more space"
end

-- Enter on a room choice. True when the mod handled it (built, or said why
-- not); the game's own click is then not used.
function M.enter(b, label)
    local cmd = M.command_of(b)
    if not cmd then return false end
    local hull = require("ship").selected_hull()
    if not (hull and hull:IsValid()) then return false end
    if not empty(hull) then
        speech.say("This space is no longer empty. Escape closes the ring.", true)
        return true
    end
    -- The ring says what stops it ("Missing resources", "Missing
    -- technology", "No available work team"); ConfirmBuild would not check.
    if label and (label:find("Missing", 1, true) or label:find("No available", 1, true)
        or label:find("Not possible", 1, true)) then
        speech.say("Cannot build. " .. label, true)
        return true
    end
    local width = cmd.Width or 1
    local start, run = M.fit(hull, width)
    if not start then
        speech.say("Cannot build here. " .. M.fit_text(b), true)
        return true
    end
    -- The name as the ring reads it; CommandName is internal ("Build
    -- EnlistedQuarter").
    local name = label and label:match("^([^%.]+)") or ""
    print(string.format("[VoyagerAccess] construction: build %s (type %s) at slot %d\n", name, tostring(cmd.RoomType), start))
    local cm = FindFirstOf("STVConstructionManager")
    local ok, err = pcall(function() cm:ConfirmBuild(start, cmd.RoomType) end)
    if not ok then
        print("[VoyagerAccess] construction: ConfirmBuild failed: " .. tostring(err) .. "\n")
        speech.say("The build did not start", true)
        return true
    end
    -- The ring stays open after a build (OnCloseRadial is only an event);
    -- the game's Escape closes it.
    speech.say("Building " .. (name ~= "" and name or "the room") .. ". Escape closes the ring.", true)
    return true
end

return M
