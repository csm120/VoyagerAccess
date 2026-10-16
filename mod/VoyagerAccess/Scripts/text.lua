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
-- XP, Crews and SectorThreat are reward icons whose names do not say the
-- reward (scan of every away mission and event reward, 2026-10-16).
local UNITS = { BioNeuralGelPack = "bio-neural gel packs", SciencePoints = "science points", Cycles = "cycles",
                Cycle = "cycles", BorgNanites = "Borg nanites", CombatPower = "combat power",
                XP = "experience", Crews = "crew", SectorThreat = "sector threat level" }
local function unit(id)
    id = id:gsub("_.*$", "")
    if UNITS[id] then return UNITS[id] end
    return (id:gsub("(%l)(%u)", "%1 %2"):lower())
end

-- A reward icon's material ("MI_UI_SciencePoints_white",
-- "MI_UI_XP_Reward_HeroPortraits") as the words for its resource, or nil.
function M.icon_name(material)
    local id = type(material) == "string" and material:gsub("^MI_UI_RichImage_", ""):match("^MI_UI_(%a+)")
        or (type(material) == "string" and material:gsub("^MI_UI_RichImage_", ""):match("^(%a+)"))
    return id and unit(id) or nil
end

local IMG = '<[Ii][Mm][Gg]%s+[Ii][Dd]%s*=%s*"([%w_]+)"%s*/>'

function M.prep(s)
    if type(s) ~= "string" or s == "" then return s or "" end
    -- An icon right after its own name ("+80 <ColorDeuterium>Deuterium</>
    -- <img id="Deuterium"/>") adds nothing; dropped first, so the rule below
    -- cannot pair it with the next line's number ("+80 Deuterium +8
    -- deuterium Duranium", Waste Disassembler, VM, 2026-10-16).
    local function own(word, id) return word:lower() == id:lower() or word:lower() .. "s" == id:lower() end
    -- Whole names in a colour tag, letters only: "SCIENCE POINTS" with
    -- SciencePoints, "EX BORG" with ExBorg, "BIO-NEURAL GEL PACK" with
    -- GelPack (all 117 icon strings in the game checked, 2026-10-16).
    s = s:gsub("(<%w+>([^<>]+)</>)[ \t]*" .. IMG, function(whole, phrase, id)
        local a, b = phrase:lower():gsub("[^%a]", ""), id:lower()
        if a == b or a .. "s" == b or a:find(b, 1, true) or b:find(a, 1, true) then return whole end
    end)
    s = s:gsub("(%a+)</>[ \t]*" .. IMG, function(word, id) if own(word, id) then return word .. "</>" end end)
    s = s:gsub("(%a+)[ \t]*" .. IMG, function(word, id) if own(word, id) then return word end end)
    -- Icon then number (a colour tag around the number is optional), on
    -- the same line only.
    s = s:gsub(IMG .. "[ \t]*<%w+>[ \t]*([%+%-]?[%d,%.]+)[ \t]*</>", function(id, n) return n .. " " .. unit(id) end)
    s = s:gsub(IMG .. "[ \t]*([%+%-]?%d[%d,%.]*)", function(id, n) return n .. " " .. unit(id) end)
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
    -- Brackets round a screen's name in capitals: "the [TECH TREE]",
    -- "[MAIN ENGINEERING]", "[WORKSHOP]" (scan of every room description,
    -- VM, 2026-10-16). Bracketed placeholders like "[{Shuttle}]" have no
    -- capitals run and are left to their readers.
    s = s:gsub("%[(%u[%u%s%-']*)%]", "%1")
    return s
end

return M
