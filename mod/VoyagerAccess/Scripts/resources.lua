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

function M.say()
    local by = {}
    for _, w in ipairs(shown_widgets("STVSingleResourceWidget")) do
        by[w:GetFName():ToString()] = w
    end
    local parts = {}
    for _, key in ipairs(ORDER) do
        local w = by[key]
        if w then
            local text = (NAMES[key] or key) .. " " .. text_of(w.CurrentResourceAmountText)
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
    if cycles then parts[#parts + 1] = "Fuel lasts " .. text_of(cycles.CyclesAmount) .. " cycles" end
    speech.say(#parts > 0 and table.concat(parts, ". ") or "Resources are not shown here", true)
end

function M.install()
    require("keys").on("c", M.say)
end

return M
