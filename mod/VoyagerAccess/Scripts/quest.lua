-- The current objective, from the quest tracker in the corner of the screen
-- (WBP_QuestLineDisplay has the quest's name, WBP_QuestDisplay each
-- objective). Spoken when it changes, and on demand with O, which the game
-- does not use (the game's own key bindings). Casey asked how he would know
-- what to do next (2026-10-10); this tracker is the only place that says.

local speech = require("speech")
local screen = require("screen")
local popups = require("popups")
local crumb = require("crumb")

local M = {}

local INTERVAL_MS = 1000

-- The last objective announced is kept in a file, so reloading the mod
-- (or restarting the game on the same objective) does not repeat it.
local LAST_PATH = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\objective.txt"
local function read_last()
    local f = io.open(LAST_PATH, "r")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end
local function write_last(s)
    local f = io.open(LAST_PATH, "w")
    if not f then return end
    f:write(s)
    f:close()
end
local last = read_last()

local function shown_texts(cls)
    local out = {}
    for _, w in ipairs(FindAllOf(cls) or {}) do
        if w:IsValid() then
            local path = w:GetFullName():match("^%S+%s+(.+)$")
            if path and path:find("^/Engine/Transient%.") and screen.shown(w) then
                local t = popups.text_under(path)
                if t ~= "" then out[#out + 1] = t end
            end
        end
    end
    return out
end

-- "Caretaker: Activate Stellar Cartography by switching the power on", or nil.
function M.objective()
    local goals = shown_texts("WBP_QuestDisplay_C")
    if #goals == 0 then return nil end
    -- [STELLAR CARTOGRAPHY] marks a highlighted name; read it as words.
    local text = table.concat(goals, ". "):gsub("%[([^%]]+)%]", function(s)
        return (s:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
    end)
    local quest = shown_texts("WBP_QuestLineDisplay_C")[1]
    return quest and (quest .. ": " .. text) or text
end

function M.say_objective()
    speech.say(M.objective() or "No objective shown", true)
end

local function poll()
    crumb.at("quest: poll")
    local now = M.objective()
    if now and now ~= last then
        print("[VoyagerAccess] objective: " .. now .. "\n")
        speech.say("Objective: " .. now, false)
        last = now
        write_last(now)
    end
end

function M.install()
    require("keys").on("o", M.say_objective)
    LoopInGameThreadWithDelay(INTERVAL_MS, function()
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] quest error: " .. tostring(err) .. "\n") end
    end)
end

return M
