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
    local out, missions = {}, {}
    for _, l in ipairs(lines) do
        if #l.goals > 0 then
            local goals = words(table.concat(l.goals, ". "))
            out[#out + 1] = l.name ~= "" and (quest_name(l.name) .. ": " .. goals) or goals
            local m = { name = l.name ~= "" and quest_name(l.name) or "", goals = {} }
            for i, g in ipairs(l.goals) do m.goals[i] = words(g) end
            missions[#missions + 1] = m
        end
    end
    if #loose > 0 then
        out[#out + 1] = words(table.concat(loose, ". "))
        local m = { name = "", goals = {} }
        for i, g in ipairs(loose) do m.goals[i] = words(g) end
        missions[#missions + 1] = m
    end
    if #out == 0 then return nil end
    return table.concat(out, ". "), missions
end

-- Countdowns and progress counts change on their own every cycle; they are
-- not a change of objective.
local function bare(s) return (s:gsub(", %d+ cycles? left", ""):gsub("%s*%(%d+/%d+%)", "")) end

-- What changed between two mission lists, as words: "Done: Assign Neelix
-- to the Mess Hall." Every step re-read the whole list, five missions long,
-- when one goal was ticked off (State of Flux, VM, 2026-10-15). nil when
-- nothing but counts changed.
function M.changes(old, new)
    local function index(list)
        local missions, goals = {}, {}
        for _, m in ipairs(list) do
            local key = bare(m.name)
            missions[key] = true
            for _, g in ipairs(m.goals) do goals[key .. "\0" .. bare(g)] = true end
        end
        return missions, goals
    end
    local old_m, old_g = index(old)
    local new_m, new_g = index(new)
    local parts = {}
    local done, ended = {}, {}
    for _, m in ipairs(old) do
        local key = bare(m.name)
        if not new_m[key] then
            ended[#ended + 1] = m.name ~= "" and m.name:gsub(", %d+ cycles? left", "") or table.concat(m.goals, ". ")
        else
            for _, g in ipairs(m.goals) do
                if not new_g[key .. "\0" .. bare(g)] then done[#done + 1] = bare(g) end
            end
        end
    end
    if #done > 0 then parts[#parts + 1] = "Done: " .. table.concat(done, ". ") end
    if #ended > 0 then parts[#parts + 1] = (#ended == 1 and "Mission ended: " or "Missions ended: ") .. table.concat(ended, ", ") end
    for _, m in ipairs(new) do
        local key = bare(m.name)
        local added = {}
        for _, g in ipairs(m.goals) do
            if not old_g[key .. "\0" .. bare(g)] then added[#added + 1] = g end
        end
        if #added > 0 then
            local goals = table.concat(added, ". ")
            local head = (not old_m[key] and m.name ~= "") and ("New mission: " .. m.name .. ": ")
                or (m.name ~= "" and ("Objective: " .. m.name .. ": ") or "Objective: ")
            parts[#parts + 1] = head .. goals
        end
    end
    if #parts == 0 then return nil end
    for i, s in ipairs(parts) do parts[i] = s:gsub("%s*%.%s*$", "") end
    return table.concat(parts, ". ") .. "."
end

function M.say_objective()
    -- In battle the quest panel is hidden; the combat goal is the one shown.
    local goal = require("combat").active() and require("combat").objective()
    if goal then return speech.say("Combat goal: " .. goal, true) end
    speech.say(M.objective() or "No objective shown", true)
end

local last_missions = nil   -- the list behind last, once read this session

local function poll()
    crumb.at("quest: poll")
    -- At the main menu the game is left: the next game loaded may be another
    -- save, and its objectives came out as "Done:" the old save's ones
    -- (Profile 03 to Profile 02, VM, 2026-10-15). It is read whole instead.
    -- Likewise between Q Trial sectors: the results screen said "Done:
    -- Leave Sector. Objective: Acquire at least 90 DURANIUM (10/90)" as the
    -- exit spent the duranium (VM, 2026-10-15).
    for _, cls in ipairs({ "WBP_MainMenu_C", "WBP_SandboxSectorResult_C", "WBP_Loading_Screen_C" }) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then
                last_missions = nil
                return
            end
        end
    end
    local now, missions = M.objective()
    -- A side mission's countdown changes every cycle; only a change in
    -- the objectives themselves is announced (VM, 2026-10-14). Progress
    -- counts too: "Store DEUTERIUM (552/900)" drops every cycle as fuel
    -- burns, and the objective was read four times in one trip (VM,
    -- 2026-10-15). O reads the current counts.
    if now and (not last or bare(now) ~= bare(last)) then
        print("[VoyagerAccess] objective: " .. now .. "\n")
        -- After the first reading, only what changed is said; the whole
        -- list is the first reading (and after a reload) and O.
        local change = last_missions and M.changes(last_missions, missions)
        speech.say(change or ("Objective: " .. now), false)
        last = now
        write_last(now)
    end
    if now then last_missions = missions end
end

function M.install()
    require("keys").on("o", M.say_objective)
    LoopInGameThreadWithDelay(INTERVAL_MS, function()
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] quest error: " .. tostring(err) .. "\n") end
    end)
end

return M
