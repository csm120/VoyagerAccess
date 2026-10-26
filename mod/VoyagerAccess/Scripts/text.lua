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
-- A resource's name in the game's language, or nil: in German "-6 energy"
-- and "5 crew" were English (firefly82's review, 2026-10-20). The game's
-- STVResourceManager:GetResourceDisplayNameById ("Energy", "Crew",
-- "Bio-neural Gel Pack"; empty for an id it does not know). In English
-- too: there the mod's own UNITS words were used instead, so only English
-- players heard the mod's names rather than the game's (2026-10-24). UNITS
-- is left for an id the game does not name.
function M.game_resource_name(id)
    local name = nil
    pcall(function()
        local s = FindFirstOf("STVResourceManager"):GetResourceDisplayNameById(id):ToString()
        if s ~= "" then name = s end
    end)
    return name
end

-- A hero attribute's name as the game shows it (STVHeroManager's
-- GetHeroAttributeName), in every language; nil only when the game gives
-- none, and the enum's own name is used. "Aufgabe Medicine" was said in
-- German (VM, 2026-10-20); English heard the enum's name, not the game's
-- (2026-10-24).
function M.hero_attribute_name(value)
    local name = nil
    pcall(function()
        local s = FindFirstOf("STVHeroManager"):GetHeroAttributeName(value):ToString()
        if s ~= "" then name = s end
    end)
    return name
end

-- A skill icon's material ("MI_UI_Science") as the game's own name for the
-- skill, through hero_attribute_name; the icon's English word only when the
-- game gives none, nil when the material names no skill word. The icon's
-- word was said in German ("Benötigt Command 29", "kein Diplomacy";
-- firefly82's review, 2026-10-24). ESTVHeroAttribute values from the
-- header dump of 2026-10-18.
local ATTRIBUTES = { Command = 0, Diplomacy = 1, Engineering = 2, Security = 3, Medicine = 4, Science = 5 }
function M.skill_icon_name(material)
    local word = type(material) == "string" and material:match("^MI_UI_(%a+)")
    if not word then return nil end
    local v = ATTRIBUTES[word]
    return (v and M.hero_attribute_name(v)) or word
end

local function unit(id)
    id = id:gsub("_.*$", "")
    local game = M.game_resource_name(id == "Crews" and "Crew" or id)
    if game then return game end
    -- tr.word: crew
    if UNITS[id] then return require("tr").word(UNITS[id]) end
    return (id:gsub("(%l)(%u)", "%1 %2"):lower())
end

-- A reward icon's material ("MI_UI_SciencePoints_white",
-- "MI_UI_XP_Reward_HeroPortraits") as the words for its resource, or nil.
function M.icon_name(material)
    local id = type(material) == "string" and material:gsub("^MI_UI_RichImage_", ""):match("^MI_UI_(%a+)")
        or (type(material) == "string" and material:gsub("^MI_UI_RichImage_", ""):match("^(%a+)"))
    return id and unit(id) or nil
end

-- Title case for a name the game shows in capitals ("KAZON RAIDER" ->
-- "Kazon Raider"), letter by letter in UTF-8: Lua's %a and lower() know
-- only A to Z, so "Kazon-Aufklärer" was said "Kazon-AufkläRer", two words
-- (firefly82's review, German game, 2026-10-23). Latin-1, Latin
-- Extended-A (Polish) and Cyrillic letters are cased; other letters (CJK)
-- pass through.
local function lower_cp(c)
    if (c >= 65 and c <= 90) or (c >= 0xC0 and c <= 0xDE and c ~= 0xD7) or (c >= 0x410 and c <= 0x42F) then return c + 32 end
    if c >= 0x400 and c <= 0x40F then return c + 80 end
    if c == 0x178 then return 0xFF end
    if (c >= 0x100 and c <= 0x137) or (c >= 0x14A and c <= 0x177) then return c % 2 == 0 and c + 1 or c end
    if (c >= 0x139 and c <= 0x148) or (c >= 0x179 and c <= 0x17E) then return c % 2 == 1 and c + 1 or c end
    return c
end
local function upper_cp(c)
    if (c >= 97 and c <= 122) or (c >= 0xE0 and c <= 0xFE and c ~= 0xF7) or (c >= 0x430 and c <= 0x44F) then return c - 32 end
    if c >= 0x450 and c <= 0x45F then return c - 80 end
    if c == 0xFF then return 0x178 end
    if (c >= 0x100 and c <= 0x137) or (c >= 0x14A and c <= 0x177) then return c % 2 == 1 and c - 1 or c end
    if (c >= 0x139 and c <= 0x148) or (c >= 0x179 and c <= 0x17E) then return c % 2 == 0 and c - 1 or c end
    return c
end
local function is_letter(c)
    if (c >= 65 and c <= 90) or (c >= 97 and c <= 122) then return true end
    return c >= 0xC0 and c ~= 0xD7 and c ~= 0xF7 and not (c >= 0x2000 and c <= 0x206F) and not (c >= 0x3000 and c <= 0x303F)
end
function M.title(s)
    if type(s) ~= "string" or s == "" then return s or "" end
    local ok, out = pcall(function()
        local parts, start = {}, true
        for _, c in utf8.codes(s) do
            if is_letter(c) then
                local l = lower_cp(c)
                parts[#parts + 1] = utf8.char(start and upper_cp(l) or l)
                start = false
            else
                parts[#parts + 1] = utf8.char(c)
                -- An apostrophe or a digit keeps the word going ("O'brien's", "3rd").
                if c >= 48 and c <= 57 then start = false
                elseif c ~= 39 and c ~= 0x2019 then start = true end
            end
        end
        return table.concat(parts)
    end)
    return ok and out or s
end

local IMG = '<[Ii][Mm][Gg]%s+[Ii][Dd]%s*=%s*"([%w_]+)"%s*/>'

-- Second words of room and system names ("Warp Core", "Cargo Bay"): a line
-- break before one is a wrapped name, not a new sentence.
local NAME_TAILS = { Core = true, Bay = true, Support = true, Engineering = true, Laboratory = true,
    Lab = true, Cartography = true, Hall = true, Quarters = true, Room = true, Office = true,
    Deflector = true, Generator = true, Array = true, Compartment = true, Matrix = true, Facility = true }
function M.name_tail(word) return NAME_TAILS[word] == true end

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
    -- An empty colour tag before an icon is a name the game left out: "Each
    -- <COLORBATTERY></> <IMG ID="BATTERY"/> -50 per CYCLE" was read "Each
    -- -50 battery per CYCLE" (ion storm alert, VM, 2026-10-18). The icon
    -- names it: "Each battery -50 per CYCLE".
    s = s:gsub("<%w+>[ \t]*</>[ \t]*" .. IMG, function(id) return unit(id) end)
    -- Icon then number (a colour tag around the number is optional), on
    -- the same line only.
    s = s:gsub(IMG .. "[ \t]*<%w+>[ \t]*([%+%-]?[%d,%.]+)[ \t]*</>", function(id, n) return n .. " " .. unit(id) end)
    s = s:gsub(IMG .. "[ \t]*([%+%-]?%d[%d,%.]*)", function(id, n) return n .. " " .. unit(id) end)
    -- Number then icon: "3 <img id="Cycles"/>".
    s = s:gsub("(%d)%s*" .. IMG, function(d, id) return d .. " " .. unit(id) end)
    -- "per" then an icon: "-2 morale per <img id="Cycle"/>" read "-2 morale
    -- per" (The Long Way Home, Q Trials, VM, 2026-10-15).
    s = s:gsub("([Pp]er)%s*" .. IMG, function(p, id) return p .. " " .. (unit(id):gsub("s$", "")) end)
    -- The other languages' "per" ("-6 HÜLLE pro <img id="Cycle"/>" was read
    -- "-6 HÜLLE pro.", German, VM, 2026-10-26): a Cycle icon still here is
    -- the word "cycle", from the mod's tables in every language.
    s = s:gsub("[ \t]*" .. IMG, function(id)
        local l = id:lower()
        if l == "cycle" or l == "cycles" then return " " .. require("tr").word("cycle") end
    end)
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
    -- Not inside a name wrapped onto two lines: "Warp / Core damaged" was
    -- read "Warp. Core damaged" (energy loss report, VM, 2026-10-18).
    s = s:gsub("(%l)[ \t]*\r?\n[\r\n%s]*(%u%l*)", function(a, word)
        if NAME_TAILS[word] then return a .. " " .. word end
        return a .. ". " .. word
    end)
    -- A heading in capitals, a line break, then a sentence: "ASTEROID FIELD /
    -- Entering an asteroid field" (Sensor Alert, VM, 2026-10-17). The next
    -- line must start like a sentence (capital, then lowercase), so a label
    -- wrapped in capitals still stays joined.
    s = s:gsub("(%u)[ \t]*\r?\n[\r\n%s]*(%u%l)", "%1. %2")
    -- The heading is usually in a style tag: "<Headline>PLASMA STORM</>" then
    -- the break (Sensor Alert, VM, 2026-10-17).
    s = s:gsub("(%u)(</%w*>)[ \t]*\r?\n[\r\n%s]*(%u%l)", "%1.%2 %3")
    return s
end

return M
