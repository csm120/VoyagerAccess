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

-- A countdown in cycles shows as digit boxes before the quest's name
-- ("03"), read "0. 3. Caretaker" (2026-10-14): say it in words.
local function quest_name(quest)
    local digits = ""
    while true do
        local d, rest = quest:match("^(%d+)%.%s+(.+)$")
        if not d then break end
        digits, quest = digits .. d, rest
    end
    local n = tonumber(digits)
    if n then quest = quest .. ", " .. n .. (n == 1 and " cycle left" or " cycles left") end
    return quest
end

-- [STELLAR CARTOGRAPHY] marks a highlighted name; read it as words.
local function words(text)
    return (text:gsub("%[([^%]]+)%]", function(s)
        return (s:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
    end))
end

-- "State of Flux: Visit the Class L Planet to search for FOOD. Pursuit of
-- Happiness, 29 cycles left: Gain +5 MORALE for 15 CYCLES (0/15)", or nil.
-- Each mission with its own objectives: they were all read under the main
-- mission's name, so a side mission's goal sounded like part of the story
-- (full game, VM, 2026-10-14). An objective's parent is its mission's
-- QuestRoot; the main mission (MainQuestLineDisplayWidget) comes first.
function M.objective()
    local lines = {}
    for _, w in ipairs(FindAllOf("WBP_QuestLineDisplay_C") or {}) do
        local path = w:IsValid() and w:GetFullName():match("^%S+%s+(.+)$")
        if path and path:find("^/Engine/Transient%.") and screen.shown(w) then
            local line = { path = path .. ".", name = popups.text_under(path), goals = {} }
            if path:find("MainQuestLineDisplayWidget", 1, true) then table.insert(lines, 1, line)
            else lines[#lines + 1] = line end
        end
    end
    local loose = {}
    for _, w in ipairs(FindAllOf("WBP_QuestDisplay_C") or {}) do
        local path = w:IsValid() and w:GetFullName():match("^%S+%s+(.+)$")
        if path and path:find("^/Engine/Transient%.") and screen.shown(w) then
            local t = popups.text_under(path):gsub("%s*%.%s*$", "")
            if t ~= "" then
                local par = w:GetParent()
                local pp = par and par:IsValid() and par:GetFullName():match("^%S+%s+(.+)$") or ""
                local home = loose
                for _, l in ipairs(lines) do
                    if pp:sub(1, #l.path) == l.path then home = l.goals end
                end
                home[#home + 1] = t
            end
        end
    end
    local out = {}
    for _, l in ipairs(lines) do
        if #l.goals > 0 then
            local goals = words(table.concat(l.goals, ". "))
            out[#out + 1] = l.name ~= "" and (quest_name(l.name) .. ": " .. goals) or goals
        end
    end
    if #loose > 0 then out[#out + 1] = words(table.concat(loose, ". ")) end
    if #out == 0 then return nil end
    return table.concat(out, ". ")
end

function M.say_objective()
    -- In battle the quest panel is hidden; the combat goal is the one shown.
    local goal = require("combat").active() and require("combat").objective()
    if goal then return speech.say("Combat goal: " .. goal, true) end
    speech.say(M.objective() or "No objective shown", true)
end

local function poll()
    crumb.at("quest: poll")
    local now = M.objective()
    -- A side mission's countdown changes every cycle; only a change in
    -- the objectives themselves is announced (VM, 2026-10-14). Progress
    -- counts too: "Store DEUTERIUM (552/900)" drops every cycle as fuel
    -- burns, and the objective was read four times in one trip (VM,
    -- 2026-10-15). O reads the current counts.
    local function bare(s) return (s:gsub(", %d+ cycles? left", ""):gsub("%(%d+/%d+%)", "")) end
    if now and (not last or bare(now) ~= bare(last)) then
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
