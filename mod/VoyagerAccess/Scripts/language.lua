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

function M.install()
    LoopInGameThreadWithDelay(1000, function()
        pcall(function()
            local c = current()
            if not c then return end
            if last and c ~= last then
                local name = NAMES[c] or NAMES[c:match("^(%a+)")] or c
                print("[VoyagerAccess] language: " .. last .. " to " .. c .. "\n")
                local back = c:match("^en") and "" or " To go back, choose English in Settings, Language."
                speech.say("Game language changed to " .. name .. "." .. back, false)
            end
            last = c
        end)
    end)
end

return M
