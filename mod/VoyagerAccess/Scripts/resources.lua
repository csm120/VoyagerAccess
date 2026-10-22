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

-- Each line's resource id, for its tooltip (Enter in the list).
local ids = {}

-- The status lines, each one item (resources, crew, fuel, energy, morale).
local function lines()
    ids = {}
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
                add(require("tr").word("Q"), am.AmusementHullChange, 1)
                if #why > 0 then t = t .. ": " .. table.concat(why, ", ") end
                -- Which state the Main Deflector is in (Damaged on deck 14,
                -- VM, 2026-10-17), so you know what to fix.
                if offline > 0 then
                    local st = require("ship").state_of("MainDeflector")
                    if st and st ~= "on" then t = t .. ". Main deflector " .. require("tr").lower(st) end
                end
            end)
            return t
        end)
        if ok and text ~= "Hull " then parts[#parts + 1] = text; ids[#parts] = "Hull" end
    end
    -- Sector Threat, a bar in the header beside the hull (WBP_ThreatLevel:
    -- Current and max, both 0 in the first sector; found from the game's
    -- widget list, 2026-10-15).
    local threat = shown_widgets("WBP_ThreatLevel_C")[1]
    if threat then
        local ok, cur, max = pcall(function() return threat.Current, threat.max end)
        if ok and type(max) == "number" and max > 0 then
            parts[#parts + 1] = "Sector threat " .. cur .. " of " .. max; ids[#parts] = "ThreatLevel"
        end
    end
    -- Torpedoes, in the header beside the threat bar
    -- (WBP_TorpedoDisplay.TorpedoCount_TextBox, "38"): shown on every map
    -- and C did not say them (map parity audit, 2026-10-21).
    local torp = shown_widgets("WBP_TorpedoDisplay_C")[1]
    if torp then
        local n = text_of(torp.TorpedoCount_TextBox)
        if n:match("^%d+$") then parts[#parts + 1] = "Torpedoes " .. tonumber(n) end
    end
    -- Storage limits: events said "storage full" and C never said how much
    -- fits (State of Flux, VM, 2026-10-15). Science points (9999) have none
    -- worth saying.
    local manager = FindFirstOf("STVResourceManager")
    for _, key in ipairs(ORDER) do
        local w = by[key]
        if w then
            -- tr.word: Food
            local text = (NAMES[key] or require("tr").word(key)) .. " " .. text_of(w.CurrentResourceAmountText)
            local okc, cap = pcall(function() return manager:GetResourceCapacity(key) end)
            if okc and type(cap) == "number" and cap > 0 and cap < 9999 then text = text .. ", max " .. cap end
            local change = text_of(w.CyclePreview)
            if change:match("^[%+%-]%d") then
                text = text .. (change:sub(1, 1) == "-" and ", minus " or ", plus ") .. change:sub(2) .. " per cycle"
            end
            parts[#parts + 1] = text; ids[#parts] = key
        end
    end
    local function team(name, label, id)
        for _, w in ipairs(shown_widgets(name)) do
            parts[#parts + 1] = label .. " " .. text_of(w.AvailableAmount) .. " of " .. text_of(w.TotalAmount) .. " available"
            ids[#parts] = id
        end
    end
    team("WBP_Crew_Resource_C", require("tr").word("Crew"), "Crew")
    -- The label in the game's language here: inside "{s} {s} of {s}
    -- available" the line pass split it, and "Work teams" stayed English
    -- (German game, 2026-10-21).
    team("WBP_WorkTeams_Resource_C", require("tr").word("Work teams"))
    local cycles = by.Cycles
    -- Not cycles passed: it went 16, then 14 as Deuterium went 396, then 348
    -- at 24 a cycle, so it is how many cycles the fuel lasts.
    if cycles then
        local n = text_of(cycles.CyclesAmount)
        parts[#parts + 1] = "Fuel lasts " .. n .. (n == "1" and " cycle" or " cycles"); ids[#parts] = "Cycles"
    end
    -- The cycles passed, under the header (WBP_HUD.WBP_PassedCycles:
    -- PassedCycle_TextBox "33" and its own label, "vergangene Zyklen" in the
    -- German game): shown on every map and C did not say it (map parity
    -- audit, 2026-10-21). The label is the game's own text, read from the
    -- widget's own tree; the zero padding (FillDigit_Text) is left out.
    local passed = shown_widgets("WBP_PassedCycles_C")[1]
    if passed then
        local n = text_of(passed.PassedCycle_TextBox)
        local label = nil
        for _, t in ipairs(screen.texts_in(passed)) do
            if not label and t:find("%a") then label = t end
        end
        if n:match("^%d+$") and label then parts[#parts + 1] = label .. " " .. tonumber(n) end
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
            .. (use ~= "" and (", rooms use " .. use) or ""); ids[#parts] = "Energy"
    end
    local battery = first("WBP_AggregateEnergy_Battery_C")
    if battery then
        local excess = text_of(battery.ExcessEnergyText):gsub("^%+", "")
        parts[#parts + 1] = "Battery " .. text_of(battery.BatteryAmount)
            .. (excess:match("^%d") and (", charging " .. excess) or "")
        -- The bar's own id for it (its ResourceString, VM, 2026-10-20).
        ids[#parts] = "Batteries"
    end
    local morale = first("WBP_Morale_03_C")
    if morale then
        -- The change per cycle is ChangeTextBlock of the bar's own
        -- HappinessWidget (USTVMoraleWidget, header dump): read there, not
        -- by searching every TextBlock in the game for its path (rule 42;
        -- the map audit found the same kind of search over every Image
        -- holding the game 55 ms, 2026-10-21).
        local change = ""
        pcall(function()
            local t = morale.HappinessWidget.ChangeTextBlock
            if t and t:IsValid() and screen.shown(t) then change = text_of(t) end
        end)
        local text = "Morale " .. text_of(morale.MoraleNumber)
        if change:match("^[%+%-]%d") then
            text = text .. (change:sub(1, 1) == "-" and ", minus " or ", plus ") .. change:sub(2) .. " per cycle"
        end
        -- The crew's conditions beside the bar, each a number by an icon
        -- (USTVMoraleWidget: SickOrInjuredWidget, HungryWidget,
        -- HomelessWidget and the others, each with MildConditionTextBlock
        -- and SevereConditionTextBlock): "3, 96, 36" on screen and C said
        -- none of them (map parity audit, 2026-10-21). Only those shown.
        local CONDITIONS = {
            { "SickOrInjuredWidget", "{n} sick or injured" }, { "SickWidget", "{n} sick" },
            { "InjuredWidget", "{n} injured" }, { "HungryWidget", "{n} hungry" },
            -- The Ex-Borg's own count: "72 homeless, 97 homeless" told
            -- them apart only by an icon (VM, 2026-10-21).
            { "HomelessWidget", "{n} homeless" }, { "HomelessWidgetExBorg", "{n} homeless Ex-Borg" },
        }
        for _, c in ipairs(CONDITIONS) do
            pcall(function()
                local w = morale[c[1]]
                if not (w and w:IsValid() and screen.shown(w)) then return end
                local mild = w.MildConditionTextBlock
                local n = (mild and mild:IsValid() and screen.shown(mild)) and text_of(mild) or ""
                if not n:match("^%d+$") then return end
                local said = ", " .. c[2]:gsub("{n}", tostring(tonumber(n)))
                local severe = w.SevereConditionTextBlock
                local m = (severe and severe:IsValid() and screen.shown(severe)) and text_of(severe) or ""
                if m:match("^%d+$") and tonumber(m) > 0 then said = said .. " (" .. tonumber(m) .. " severe)" end
                text = text .. said
            end)
        end
        parts[#parts + 1] = text; ids[#parts] = "Morale"
    end
    return parts
end

-- C opens the status as a list, one item at a time (Casey, 2026-10-11:
-- "each item on its own line"): Up and Down move, Home and End go to the
-- ends, Backspace or C again closes it.
local items, index = nil, nil
-- A details list (what the game's tooltip shows for one thing) uses the same
-- keys; back is the list it was opened from, which Backspace or Escape
-- returns to (Casey, 2026-10-19: "all the info in a list they can take
-- their time with", closed like the other lists).
local back = nil
local item_ids = nil
local in_details = false

local function say_item()
    speech.say(string.format("%s, %d of %d", items[index], index, #items), true)
end

function M.list_open()
    return items ~= nil
end

-- Opens lines as a list; title is said first.
function M.show_details(title, list)
    if #list == 0 then
        speech.say("No details here", true)
        return
    end
    back = items and { items = items, index = index } or nil
    in_details = true
    items, index = list, 1
    require("focus").park_focus()
    speech.say(title .. ".", true)
    speech.say(string.format("%s, %d of %d", items[index], index, #items), false)
end

function M.say()
    if items then
        items, back, in_details = nil, nil, false
        speech.say("Closed", true)
        return
    end
    local parts = lines()
    if #parts == 0 then
        speech.say("Resources are not shown here", true)
        return
    end
    -- One of the mod's lists at a time: C over the open J list left the
    -- arrows moving the room list under it (firefly82, 2026-10-21).
    require("ship").list_dismiss()
    items, index = parts, 1
    item_ids = ids
    require("focus").park_focus()
    say_item()
end

-- Enter on a line of C: the game's tooltip for it as a details list
-- (Casey, 2026-10-19), what a sighted player reads hovering the bar.
-- In a details list Enter says the item again.
function M.enter()
    if in_details then return say_item() end
    local id = item_ids and item_ids[index]
    if not id then
        speech.say("No details for this line", true)
        return
    end
    local ok, list = pcall(function() return require("tooltip").resource_lines(id) end)
    if not ok then print("[VoyagerAccess] details error: " .. tostring(list) .. "\n") list = {} end
    M.show_details(items[index], list)
end

function M.step(dir)
    if items[index + dir] then index = index + dir end
    say_item()
end

function M.edge(last)
    index = last and #items or 1
    say_item()
end

-- Closed without a word when another of the mod's lists opens over it.
function M.dismiss()
    items, back, in_details = nil, nil, false
end

function M.close()
    if not items then return false end
    in_details = false
    if back then
        items, index, back = back.items, back.index, nil
        say_item()
        return true
    end
    items = nil
    speech.say("Closed", true)
    return true
end

function M.install()
    require("keys").on("c", M.say)
end

return M
