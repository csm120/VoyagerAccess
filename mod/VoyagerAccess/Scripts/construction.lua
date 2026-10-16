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

-- The ring's centre fills only on a real mouse hover, and on a forum
-- player's computer the game ignored the mouse (2026-10-16). Hooking the
-- centre showed the game calls OnSetRoom(level config, type config, cycles,
-- 0); calling it from Lua fills only part of the centre (name, description
-- and costs are set natively), so the same reading is built from the data:
-- DA_RoomConfig's Configs (type config) and GetRoomConfig (level 0), the
-- room text generator's description (it wants the type config), and the
-- command's CanExecute and IsHardLocked_BP with the construction manager
-- as context (the ring's CommandContextObject). Missing technology is a
-- hard lock; the other reasons are checked here.
local ROOM_CONFIG = "/Game/STVoyager/ConstructionSideview/Data/DA_RoomConfig.DA_RoomConfig"

local function clean(s)
    s = require("text").prep(s)
    return (s:gsub("<[^>]*>", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

function M.blocked(cmd, cm, cfg, tc)
    local ok, can = pcall(function() return cmd:CanExecute(cm) end)
    if not ok or can then return nil end
    local hard = false
    pcall(function() hard = cmd:IsHardLocked_BP(cm) end)
    if hard then return "Missing technology" end
    local hull = require("ship").selected_hull()
    local ls = true
    pcall(function()
        if tc.bRequiresLifesupport and hull then ls = cm:IsLifeSupportActiveForSlot(hull:BP_GetSlotIndex()) end
    end)
    if not ls then return "No life support" end
    local rm = FindFirstOf("STVResourceManager")
    -- Free work teams: the HUD counter C reads. The resource "WorkTeams"
    -- lags (still 1 with C saying "Work teams 0 of 2 available", VM,
    -- 2026-10-16).
    local teams = true
    pcall(function()
        for _, w in ipairs(FindAllOf("WBP_WorkTeams_Resource_C") or {}) do
            if w:IsValid() and require("screen").shown(w) then
                local n = tonumber((w.AvailableAmount:GetText():ToString():match("%d+")))
                if n then teams = n >= cfg.RequiredWorkTeamsToBuild end
            end
        end
    end)
    if not teams then return "No available work team" end
    local short = false
    pcall(function()
        cfg.RequiredResourcesToBuild:ForEach(function(_, e)
            local r = e:get()
            if rm:GetResourceAmount(r.ResourceName:ToString(), false) < r.ResourceAmount then short = true end
        end)
    end)
    if short then return "Missing resources" end
    return "Not possible now"
end

-- What the centre would say for a room choice: { text, check }, check being
-- the start of the description, to tell whether a hover reached this room.
function M.ring_text(b)
    local cmd = M.command_of(b)
    if not cmd then return nil end
    local t = cmd.RoomType
    local rc = StaticFindObject(ROOM_CONFIG)
    if not (rc and rc:IsValid()) then return nil end
    local tc = nil
    rc.Configs:ForEach(function(k, v) if k:get() == t then tc = v:get() end end)
    local out = {}
    rc:GetRoomConfig(t, 0, out)
    local cfg = out.OutConfig
    if not (tc and tc:IsValid() and cfg and cfg:IsValid()) then return nil end
    local cm = FindFirstOf("STVConstructionManager")
    local desc = ""
    pcall(function() desc = clean(cm:GetRoomTextGenerator(cm):GetRoomDescriptionText(t, tc, 0):ToString()) end)
    local parts = { require("ship").type_name(t) }
    local why = M.blocked(cmd, cm, cfg, tc)
    if why then parts[#parts + 1] = why end
    if desc ~= "" then parts[#parts + 1] = desc end
    parts[#parts + 1] = string.format("Operation: energy %d, crew %d", math.floor(cfg.EnergyCostWhenActive + 0.5), math.floor(cfg.RequiredCrewMembersToOperate + 0.5))
    local build = {}
    cfg.RequiredResourcesToBuild:ForEach(function(_, e)
        local r = e:get()
        -- "BioneuralGelPack" here (VM, 2026-10-16); the others read as the
        -- centre has them ("50 Duranium").
        local name = r.ResourceName:ToString()
        if name:lower() == "bioneuralgelpack" then name = "bio-neural gel packs"
        else name = name:gsub("(%l)(%u)", "%1 %2") end
        build[#build + 1] = r.ResourceAmount .. " " .. name
    end)
    local wt, cy = cfg.RequiredWorkTeamsToBuild, cfg.CyclesToBuild
    build[#build + 1] = wt .. (wt == 1 and " work team" or " work teams")
    build[#build + 1] = cy .. (cy == 1 and " cycle" or " cycles")
    parts[#parts + 1] = "Construction: " .. table.concat(build, ", ")
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    return { text = table.concat(parts, ". "), check = desc:sub(1, 30) }
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
    -- Where it fits first: that reason is more exact than the game's
    -- "Not possible now" (review, 2026-10-16).
    local width = cmd.Width or 1
    local start, run = M.fit(hull, width)
    if not start then
        speech.say("Cannot build here. " .. M.fit_text(b), true)
        return true
    end
    -- The game's own check, for when the reading came from the data and the
    -- label has no reason in it.
    local cm0 = FindFirstOf("STVConstructionManager")
    local okb, why = pcall(function()
        local rc = StaticFindObject(ROOM_CONFIG)
        local tc = nil
        rc.Configs:ForEach(function(k, v) if k:get() == cmd.RoomType then tc = v:get() end end)
        local out = {}
        rc:GetRoomConfig(cmd.RoomType, 0, out)
        return M.blocked(cmd, cm0, out.OutConfig, tc)
    end)
    if okb and why then
        speech.say("Cannot build. " .. why, true)
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
    -- The game can refuse with no error: in a Q Trial, ConfirmBuild on a
    -- just-cleared space did nothing and "Building Cargo Bay" was said
    -- (VM, 2026-10-16). Check the space really has work under way.
    local started = false
    pcall(function()
        local a, b2 = {}, {}
        cm:GetRoomCurrentActionTimeBySlot(start, a, b2)
        started = (a.OutRemainingCycles or -1) > 0
        if not started then
            for _, h in ipairs(FindAllOf("STVRoomHull") or {}) do
                if h:IsValid() and h:BP_GetSlotIndex() == start and h:GetRoomType() ~= 0 then started = true end
            end
        end
    end)
    if not started then
        print("[VoyagerAccess] construction: ConfirmBuild did not start a build at " .. start .. "\n")
        speech.say("The game did not start the build here. Escape closes the ring.", true)
        return true
    end
    -- The ring stays open after a build, on its room page (OnCloseRadial is
    -- only an event). Left open, it sat behind the next offer and then
    -- behind Game Over, and its categories took the arrows there (VM,
    -- 2026-10-15). GoBackToLastMenu steps back one level a call: the first
    -- reaches the categories, the second closes the ring.
    speech.say("Building " .. (name ~= "" and name or "the room"), true)
    ExecuteInGameThreadWithDelay(300, function()
        pcall(function()
            for _ = 1, 3 do
                local open = nil
                for _, w in ipairs(FindAllOf("WBP_RadialMenu_C") or {}) do
                    if w:IsValid() and require("screen").shown(w) then open = w end
                end
                if not open then break end
                open:GoBackToLastMenu()
            end
        end)
    end)
    return true
end

return M
