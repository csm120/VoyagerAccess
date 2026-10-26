-- Says so when the game's language changes. Moving through the Language
-- setting applies each language at once, and twice in the VM the game was
-- left in German or Spanish by a stray key (2026-10-15 and 2026-10-16), with
-- every label then read in that language and no word about what happened.
local M = {}
local speech = require("speech")

local NAMES = { en = "English", de = "German", es = "Spanish", fr = "French", it = "Italian",
    pl = "Polish", ru = "Russian", ja = "Japanese", ko = "Korean", ["zh-Hans"] = "Chinese",
    ["pt-BR"] = "Portuguese", tr = "Turkish", cs = "Czech", uk = "Ukrainian" }

local last = nil

local function current()
    local k = StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary")
    return k and k:GetCurrentCulture():ToString() or nil
end

-- True when the game is in English, or the language cannot be read. For
-- checks that know an English word but also have a fallback by widget name.
function M.english()
    local ok, c = pcall(current)
    return not (ok and c) or c:match("^en") ~= nil
end

local function mod_name(c)
    local name = NAMES[c] or NAMES[c:match("^(%a+)")]
    return name and require("tr").word(name) or c
end

-- Reads the language once and says a change. now and before (optional):
-- the Language row's value after and before the key, as the row shows it
-- (the game's own names, "Deutsch", "русский"); without them the mod's
-- names for the languages.
function M.check(why, now, before)
    pcall(function()
        local c = current()
        if not c then return end
        -- The translations follow at once (tr.lua reads the language again).
        if c ~= last then require("tr").culture_changed() end
        if last and c ~= last then
            print("[VoyagerAccess] language: " .. last .. " to " .. c .. " (after " .. why .. ")\n")
            local tr = require("tr")
            -- Back to the language the player came from: it always named
            -- English, and back in German said "choose English" (2026-10-25).
            local back = tr.fill("To go back, choose {s} in Settings, Language.", before or mod_name(last))
            speech.say(tr.fill("Game language changed to {s}.", now or mod_name(c)) .. " " .. back, false, true)
        end
        last = c
    end)
end

-- The game changes the language in its own code: its settings row takes
-- Left and Right and the mouse, and none of the row's functions that can be
-- hooked runs then (probe 2026-10-25: only the mod's own calls came
-- through). So the language is read once after each input, as focus is
-- (keys.lua): a single call, no search. It was asked for once a second all
-- game long.
function M.install()
    M.check("start")
    require("keys").on_any(function() M.check("input") end)
    print("[VoyagerAccess] language: read after each input\n")
end

return M
