-- C (for cargo) reads the resource bar along the top of the screen, which
-- the Basic Resources tutorial points to and nothing else speaks. C is
-- unbound in the game (the game uses A D E F M Q S T W).
--
-- Each resource is an STVSingleResourceWidget named after the resource
-- (Deuterium, Duranium, ...) with CurrentResourceAmountText and CyclePreview
-- ("-24" per cycle, "-" for none). Crew and work teams show AvailableAmount
-- and TotalAmount; Cycles shows CyclesAmount, the cycles the Deuterium lasts.
-- Read 2026-10-11.

local speech = require("speech")
local screen = require("screen")

local M = {}

-- Spoken order: fuel and building materials first.
local ORDER = { "Deuterium", "Duranium", "Tritanium", "Food", "Dilithium",
    "SciencePoints", "BioNeuralGelPack", "BorgNanites" }
local NAMES = { SciencePoints = "Science points", BioNeuralGelPack = "Bio-neural gel packs",
    BorgNanites = "Borg nanites" }

local function text_of(w)
    if not (w and w:IsValid()) then return "" end
    local ok, s = pcall(function() return w:GetText():ToString() end)
    return ok and s or ""
end

local function shown_widgets(cls)
    local out = {}
    for _, w in ipairs(FindAllOf(cls) or {}) do
        local p = w:IsValid() and w:GetFullName():match("^%S+%s+(.+)$")
        if p and p:find("^/Engine/Transient%.") and screen.shown(w) then out[#out + 1] = w end
    end
    return out
end

-- The status lines, each one item (resources, crew, fuel, energy, morale).
local function lines()
    local by = {}
    for _, w in ipairs(shown_widgets("STVSingleResourceWidget")) do
        by[w:GetFName():ToString()] = w
    end
    local parts = {}
    -- Hull integrity, in the header beside morale (WBP_HullIntegrity:
    -- CurrentHullValue, HullValuePerCycle). It fell from 150 to 60 while the
    -- deflector was off and C never said so (2026-10-14).
    local hull = shown_widgets("WBP_HullIntegrity_C")[1]
    if hull then
        local ok, text = pcall(function()
            local t = "Hull " .. text_of(hull.CurrentHullValue)
            local change = text_of(hull.HullValuePerCycle)
            if change:match("^[%+%-]%d") then
                t = t .. (change:sub(1, 1) == "-" and ", minus " or ", plus ") .. change:sub(2) .. " per cycle"
            end
            -- Where the change comes from, as the hull's hover tooltip shows
            -- it: "minus 12 per cycle" with no reason left no way to tell
            -- that the offline deflector cost 15 a cycle (VM, 2026-10-17;
            -- HullDepletionMovement is the tooltip's "Deflector Offline", and
            -- it applies standing still too). Out parameters of
            -- STVConstructionManager:GetNextCycleHullChangeInfo.
            pcall(function()
                local cm = FindFirstOf("STVConstructionManager")
                local mv, ph, df, rp, cost, tm, rm, am = {}, {}, {}, {}, {}, {}, {}, {}
                cm:GetNextCycleHullChangeInfo(mv, ph, df, rp, cost, tm, rm, am)
                local why = {}
                local function add(name, n, sign)
                    n = math.floor((tonumber(n) or 0) * sign + 0.5)
                    if n > 0 then why[#why + 1] = name .. " plus " .. n
                    elseif n < 0 then why[#why + 1] = name .. " minus " .. -n end
                end
                -- A working deflector deflects the same amount ("minus 15,
                -- deflected plus 15" once repaired), so only the rest counts.
                local offline = (tonumber(mv.HullDepletionMovement) or 0) - (tonumber(df.DeflectedHullDamage) or 0)
                add("deflector offline", math.max(offline, 0), -1)
                add("plasma storm or asteroid field", ph.HullDepletionPhenomena, -1)
                add("repairs", rp.HullRepair, 1)
                add("rooms", rm.RoomHullChange, 1)
                add("Q", am.AmusementHullChange, 1)
                if #why > 0 then t = t .. ": " .. table.concat(why, ", ") end
                -- Which state the Main Deflector is in (Damaged on deck 14,
                -- VM, 2026-10-17), so you know what to fix.
                if offline > 0 then
                    local st = require("ship").state_of("MainDeflector")
                    if st and st ~= "on" then t = t .. ". Main deflector " .. st:lower() end
                end
            end)
            return t
        end)
        if ok and text ~= "Hull " then parts[#parts + 1] = text end
    end
    -- Sector Threat, a bar in the header beside the hull (WBP_ThreatLevel:
    -- Current and max, both 0 in the first sector; found from the game's
    -- widget list, 2026-10-15).
    local threat = shown_widgets("WBP_ThreatLevel_C")[1]
    if threat then
        local ok, cur, max = pcall(function() return threat.Current, threat.max end)
        if ok and type(max) == "number" and max > 0 then
            parts[#parts + 1] = "Sector threat " .. cur .. " of " .. max
        end
    end
    -- Storage limits: events said "storage full" and C never said how much
    -- fits (State of Flux, VM, 2026-10-15). Science points (9999) have none
    -- worth saying.
    local manager = FindFirstOf("STVResourceManager")
    for _, key in ipairs(ORDER) do
        local w = by[key]
        if w then
            local text = (NAMES[key] or key) .. " " .. text_of(w.CurrentResourceAmountText)
            local okc, cap = pcall(function() return manager:GetResourceCapacity(key) end)
            if okc and type(cap) == "number" and cap > 0 and cap < 9999 then text = text .. ", max " .. cap end
            local change = text_of(w.CyclePreview)
            if change:match("^[%+%-]%d") then
                text = text .. (change:sub(1, 1) == "-" and ", minus " or ", plus ") .. change:sub(2) .. " per cycle"
            end
            parts[#parts + 1] = text
        end
    end
    local function team(name, label)
        for _, w in ipairs(shown_widgets(name)) do
            parts[#parts + 1] = label .. " " .. text_of(w.AvailableAmount) .. " of " .. text_of(w.TotalAmount) .. " available"
        end
    end
    team("WBP_Crew_Resource_C", "Crew")
    team("WBP_WorkTeams_Resource_C", "Work teams")
    local cycles = by.Cycles
    -- Not cycles passed: it went 16, then 14 as Deuterium went 396, then 348
    -- at 24 a cycle, so it is how many cycles the fuel lasts.
    if cycles then
        local n = text_of(cycles.CyclesAmount)
        parts[#parts + 1] = "Fuel lasts " .. n .. (n == "1" and " cycle" or " cycles")
    end
    -- The rest of the strip (2026-10-11): energy (WBP_AggregateEnergy_Energy:
    -- CurrentResourceAmountText the output, UpkeepAmountText what rooms
    -- use), the battery (BatteryAmount stored, ExcessEnergyText the surplus
    -- going in) and morale (MoraleNumber, ChangeTextBlock per cycle).
    local function first(cls)
        return shown_widgets(cls)[1]
    end
    local energy = first("WBP_AggregateEnergy_Energy_C")
    if energy then
        local use = text_of(energy.UpkeepAmountText):gsub("^%-", "")
        parts[#parts + 1] = "Energy " .. text_of(energy.CurrentResourceAmountText)
            .. (use ~= "" and (", rooms use " .. use) or "")
    end
    local battery = first("WBP_AggregateEnergy_Battery_C")
    if battery then
        local excess = text_of(battery.ExcessEnergyText):gsub("^%+", "")
        parts[#parts + 1] = "Battery " .. text_of(battery.BatteryAmount)
            .. (excess:match("^%d") and (", charging " .. excess) or "")
    end
    local morale = first("WBP_Morale_03_C")
    if morale then
        -- ChangeTextBlock is not a property of the widget; find it by path.
        local change = ""
        local mp = morale:GetFullName():match("^%S+%s+(.+)$") .. "."
        for _, t in ipairs(FindAllOf("TextBlock") or {}) do
            local p = t:IsValid() and t:GetFullName():match("^%S+%s+(.+)$")
            if p and p:sub(1, #mp) == mp and p:find("%.ChangeTextBlock$") and screen.shown(t) then change = text_of(t) end
        end
        local text = "Morale " .. text_of(morale.MoraleNumber)
        if change:match("^[%+%-]%d") then
            text = text .. (change:sub(1, 1) == "-" and ", minus " or ", plus ") .. change:sub(2) .. " per cycle"
        end
        parts[#parts + 1] = text
    end
    return parts
end

-- C opens the status as a list, one item at a time (Casey, 2026-10-11:
-- "each item on its own line"): Up and Down move, Home and End go to the
-- ends, Backspace or C again closes it.
local items, index = nil, nil

local function say_item()
    speech.say(string.format("%s, %d of %d", items[index], index, #items), true)
end

function M.list_open()
    return items ~= nil
end

function M.say()
    if items then
        items = nil
        speech.say("Closed", true)
        return
    end
    local parts = lines()
    if #parts == 0 then
        speech.say("Resources are not shown here", true)
        return
    end
    items, index = parts, 1
    require("focus").park_focus()
    say_item()
end

function M.step(dir)
    if items[index + dir] then index = index + dir end
    say_item()
end

function M.edge(last)
    index = last and #items or 1
    say_item()
end

function M.close()
    if not items then return false end
    items = nil
    speech.say("Closed", true)
    return true
end

function M.install()
    require("keys").on("c", M.say)
end

return M
