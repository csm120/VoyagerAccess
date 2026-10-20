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

local ROOM_CONFIG = "/Game/STVoyager/ConstructionSideview/Data/DA_RoomConfig.DA_RoomConfig"

local function empty(h)
    return h ~= nil and h:GetRoomType() == 0
end

-- A room's footprint, in spaces wide and decks tall: its level 0 config's
-- Extent. The ring command's Width is 2 for every room and is not the
-- footprint: a Phaser Control Room is 4 by 1, a Bio Lab 3 by 1, a Holodeck
-- 3 by 3, and ConfirmBuild quietly refused a Phaser room on 3 free spaces
-- (VM, 2026-10-16; the game's own mouse footprint covered 4 cells).
function M.extent(t)
    local w, d = 2, 1
    pcall(function()
        local out = {}
        StaticFindObject(ROOM_CONFIG):GetRoomConfig(t, 0, out)
        local e = out.OutConfig.Extent
        w, d = math.floor(e.X + 0.5), math.floor(e.Y + 0.5)
    end)
    return math.max(w, 1), math.max(d, 1)
end

-- Slots are cells of the room grid, numbered along a deck row and down
-- the decks a row at a time (STVRoomGrid:GetGridWidth, 88). A room is
-- built from its top left cell: the Holodeck's hull at 399 (deck 4) sits
-- on deck 6.
local function grid_width()
    local ok, w = pcall(function() return FindFirstOf("STVRoomGrid"):GetGridWidth() end)
    return (ok and w and w > 0) and w or 88
end

local function empty_slots()
    local by = {}
    for _, h in ipairs(FindAllOf("STVRoomHull") or {}) do
        if h:IsValid() and path_of(h):find("PersistentLevel", 1, true) and h:GetRoomType() == 0 then
            by[h:BP_GetSlotIndex()] = true
        end
    end
    return by
end

-- Where a room of this footprint fits so that it covers the selected
-- space: its top left slot (the selected space itself when it can be), and
-- how many empty spaces side by side there are on the selected deck.
function M.fit(hull, width, decks)
    decks = decks or 1
    local free = empty_slots()
    local gw = grid_width()
    local s = hull:BP_GetSlotIndex()
    local function fits(a)
        for r = 0, decks - 1 do
            for c = 0, width - 1 do
                if not free[a + c + r * gw] then return false end
            end
        end
        return true
    end
    local start = nil
    for r = 0, decks - 1 do
        for c = 0, width - 1 do
            if not start and fits(s - c - r * gw) then start = s - c - r * gw end
        end
    end
    local first, last = s, s
    while free[first - 1] do first = first - 1 end
    while free[last + 1] do last = last + 1 end
    return start, last - first + 1
end

local function spaces(n)
    return n .. (n == 1 and " space" or " spaces")
end

local function size_text(w, d)
    if d > 1 then return spaces(w) .. " wide and " .. d .. " decks tall" end
    return require("tr").fill("{s} wide", spaces(w))
end

-- Added to a room choice's reading: its size and whether it fits.
function M.fit_text(b)
    local cmd = M.command_of(b)
    if not cmd then return nil end
    local hull = require("ship").selected_hull()
    if not (hull and hull:IsValid() and empty(hull)) then return nil end
    local w, d = M.extent(cmd.RoomType)
    local start, run = M.fit(hull, w, d)
    if start then return size_text(w, d) .. ", fits here" end
    if d > 1 and run >= w then
        return size_text(w, d) .. ", does not fit: it needs " .. spaces(w) .. " empty side by side on "
            .. d .. " decks, one under the other. Clear ruined rooms for more space"
    end
    return size_text(w, d) .. ", does not fit: " .. (run == 1 and "this empty space is 1 wide"
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

local function clean(s)
    s = require("text").prep(s)
    return (s:gsub("<[^>]*>", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- "BioneuralGelPack" in the room configs (VM, 2026-10-16); the others read
-- as the centre has them ("50 Duranium").
local function res_name(name)
    if name:lower() == "bioneuralgelpack" then return "bio-neural gel packs" end
    return (name:gsub("(%l)(%u)", "%1 %2"))
end

local function shortages(cfg, rm)
    local short = {}
    pcall(function()
        cfg.RequiredResourcesToBuild:ForEach(function(_, e)
            local r = e:get()
            local name = r.ResourceName:ToString()
            local have = rm:GetResourceAmount(name, false)
            if have < r.ResourceAmount then
                short[#short + 1] = res_name(name) .. ", " .. math.floor(have) .. " of " .. r.ResourceAmount
            end
        end)
    end)
    return #short > 0 and table.concat(short, "; ") or nil
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
    -- Which ones and how many you have: a sighted player sees the short cost
    -- in red; "Missing resources" alone sent you to C to work it out (VM,
    -- 2026-10-17).
    local short = shortages(cfg, rm)
    if short then return "Missing resources: " .. short end
    return "Not possible now"
end

-- The game's own centre says "Missing resources." with no detail: which
-- ones, for focus.lua to add after it.
function M.shortages(b)
    local cmd = M.command_of(b)
    if not cmd then return nil end
    local rc = StaticFindObject(ROOM_CONFIG)
    if not (rc and rc:IsValid()) then return nil end
    local out = {}
    rc:GetRoomConfig(cmd.RoomType, 0, out)
    local cfg = out.OutConfig
    local rm = FindFirstOf("STVResourceManager")
    if not (cfg and cfg:IsValid() and rm and rm:IsValid()) then return nil end
    return shortages(cfg, rm)
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
        build[#build + 1] = r.ResourceAmount .. " " .. res_name(r.ResourceName:ToString())
    end)
    local wt, cy = cfg.RequiredWorkTeamsToBuild, cfg.CyclesToBuild
    build[#build + 1] = wt .. (wt == 1 and " work team" or " work teams")
    build[#build + 1] = cy .. (cy == 1 and " cycle" or " cycles")
    parts[#parts + 1] = "Construction: " .. table.concat(build, ", ")
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    return { text = table.concat(parts, ". "), check = desc:sub(1, 30), why = why and why:gsub("%.%s*$", "") }
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
    -- Where it fits first: that reason is more exact than the game's
    -- "Not possible now" (review, 2026-10-16).
    local start = M.fit(hull, M.extent(cmd.RoomType))
    if not start then
        speech.say("Cannot build here. " .. M.fit_text(b), true)
        return true
    end
    -- The game's own check, now. The ring's reading can be out of date:
    -- with the duranium just in, "Cannot build. Missing resources" was said
    -- from it (VM, 2026-10-17). The reading is used only when the check
    -- cannot be made.
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
    if not okb and label and (label:find("Missing", 1, true) or label:find("No available", 1, true)
        or label:find("Not possible", 1, true)) then
        speech.say("Cannot build. " .. label, true)
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
