-- Shared clean-up for the game's rich text, run by each reader's plain()
-- before it strips tags. Found by scanning every string the game ships
-- (tools\datadump, 2026-10-15):
--   * an icon is the only unit beside a number: "They will conclude in 3
--     <img id="Cycles"/>." was read "in 3 ."; costs drawn as
--     <img id="Duranium"/> 15 were read as a bare 15;
--   * line breaks with no punctuation before them ran list items together:
--     "Deuterium +20 Food +20 Duranium +20".

local M = {}

-- "SciencePoints" -> "science points", "BioNeuralGelPack" -> "bio-neural gel packs"
local UNITS = { BioNeuralGelPack = "bio-neural gel packs", SciencePoints = "science points", Cycles = "cycles",
                Cycle = "cycles", BorgNanites = "Borg nanites", CombatPower = "combat power" }
local function unit(id)
    if UNITS[id] then return UNITS[id] end
    return (id:gsub("_.*$", ""):gsub("(%l)(%u)", "%1 %2"):lower())
end

local IMG = '<[Ii][Mm][Gg]%s+[Ii][Dd]%s*=%s*"([%w_]+)"%s*/>'

function M.prep(s)
    if type(s) ~= "string" or s == "" then return s or "" end
    -- Icon then number (a colour tag around the number is optional).
    s = s:gsub(IMG .. "%s*<%w+>%s*([%+%-]?[%d,%.]+)%s*</>", function(id, n) return n .. " " .. unit(id) end)
    s = s:gsub(IMG .. "%s*([%+%-]?%d[%d,%.]*)", function(id, n) return n .. " " .. unit(id) end)
    -- Number then icon: "3 <img id="Cycles"/>".
    s = s:gsub("(%d)%s*" .. IMG, function(d, id) return d .. " " .. unit(id) end)
    -- "per" then an icon: "-2 morale per <img id="Cycle"/>" read "-2 morale
    -- per" (The Long Way Home, Q Trials, VM, 2026-10-15).
    s = s:gsub("([Pp]er)%s*" .. IMG, function(p, id) return p .. " " .. (unit(id):gsub("s$", "")) end)
    -- A name already said before the number: "TRITANIUM +30 tritanium" and
    -- "FOOD -150 food" in event results (Q Trials, VM, 2026-10-15) read
    -- "+30 tritanium". Tags may still be around the name.
    local function same(name, n, word)
        if name:lower() == word:lower() then return n .. " " .. word end
    end
    s = s:gsub("(%u[%u%-]+)%s*</%w*>%s*([%+%-][%d,]+) (%a[%a%-]*)", same)
    s = s:gsub("(%u[%u%-]+)%s+([%+%-][%d,]+) (%a[%a%-]*)", same)
    -- A line break right after a number is a list ("Deuterium +20 / Food
    -- +20"); after a word it can be a label wrapped onto two lines
    -- ("CURRENTLY NO / CRAFTABLE BLUEPRINTS"), so only numbers get a comma.
    s = s:gsub("([%d%%])[ \t]*\r?\n[\r\n%s]*", "%1, ")
    -- A line that starts with a number is a list item too: "750 DEUTERIUM
    -- storage capacity / 750 FOOD storage capacity" (Cargo Bay upgrade,
    -- VM, 2026-10-15).
    s = s:gsub("(%a)[ \t]*\r?\n[\r\n%s]*([%+%-]?%d)", "%1, %2")
    -- A lowercase word, a line break, then a capital starts a new sentence:
    -- "storage capacity / Changes ENERGY consumption". Labels wrapped onto
    -- two lines are all capitals, so they stay joined.
    s = s:gsub("(%l)[ \t]*\r?\n[\r\n%s]*(%u)", "%1. %2")
    return s
end

return M
