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
-- not a change of objective. A lone count too: "Treat the sick before the
-- disease spreads. (38)" became (45) and was said as "Done: ..." and then
-- as a new objective (Outbreak, VM, 2026-10-16). And a countdown inside the
-- goal: "Complete all of the following tasks within 36 CYCLES" was said as
-- "Done: ..." every cycle (Scorpion, VM, 2026-10-17).
local function bare(s)
    -- "(1,000/900)" has a comma (Deuterium running low, VM, 2026-10-17).
    return (s:gsub(", %d+ cycles? left", ""):gsub("%s*%([%d,]+/[%d,]+%)", ""):gsub("%s*%([%d,]+%)", "")
        :gsub("([Ww]ithin) %d+ ", "%1 "))
end

-- What changed between two mission lists, as words: "Done: Assign Neelix
-- to the Mess Hall." Every step re-read the whole list, five missions long,
-- when one goal was ticked off (State of Flux, VM, 2026-10-15). nil when
-- nothing but counts changed.
-- A goal whose only change is a number ("-5 FOOD per cycle" became "-10
-- FOOD per cycle") was said as "Done:" and then as a new objective
-- (Tribble Trouble, VM, 2026-10-17). It is said as changed instead.
local function shape(s) return (bare(s):gsub("[%+%-]?%d[%d,%.]*", "#")) end

-- Goals said as "Done" lately (bare text to os.clock()). When one of them
-- comes back, the goal that went away with it was not done: switching the
-- Holodeck off brought back "You need an active HOLO DECK" and dropped
-- "Wait until the crew completes their simulation training", which was said
-- as "Done: Wait until..." (Dark Frontier, VM, 2026-10-18).
local recent_done = {}

function M.changes(old, new)
    local function index(list)
        local missions, goals, shapes = {}, {}, {}
        for _, m in ipairs(list) do
            local key = bare(m.name)
            missions[key] = true
            for _, g in ipairs(m.goals) do
                goals[key .. "\0" .. bare(g)] = true
                shapes[key .. "\0" .. shape(g)] = true
            end
        end
        return missions, goals, shapes
    end
    local old_m, old_g, old_s = index(old)
    local new_m, new_g, new_s = index(new)
    local parts = {}
    local done, ended = {}, {}
    for _, m in ipairs(old) do
        local key = bare(m.name)
        if not new_m[key] then
            ended[#ended + 1] = m.name ~= "" and m.name:gsub(", %d+ cycles? left", "") or table.concat(m.goals, ". ")
        else
            for _, g in ipairs(m.goals) do
                if not new_g[key .. "\0" .. bare(g)] and not new_s[key .. "\0" .. shape(g)] then done[#done + 1] = (g:gsub("%s*%([%d,]+/[%d,]+%)", "")) end
            end
        end
    end
    local back = false
    local now = os.clock()
    for _, m in ipairs(new) do
        local key = bare(m.name)
        for _, g in ipairs(m.goals) do
            local t = recent_done[bare(g)]
            -- Within seconds only: "Accept COMMS request" comes back as the
            -- next step after real progress all the time, and the research
            -- that finished just before it was said as "On hold" (Endgame,
            -- VM, 2026-10-19). The Holodeck flip-flop is a power toggle away.
            if not old_g[key .. "\0" .. bare(g)] and t and now - t < 20 then back = true end
        end
    end
    if #done > 0 then
        if back then
            parts[#parts + 1] = "On hold: " .. table.concat(done, ". ")
        else
            parts[#parts + 1] = "Done: " .. table.concat(done, ". ")
            for _, g in ipairs(done) do recent_done[bare(g)] = now end
        end
    end
    if #ended > 0 then parts[#parts + 1] = (#ended == 1 and "Mission ended: " or "Missions ended: ") .. table.concat(ended, ", ") end
    for _, m in ipairs(new) do
        local key = bare(m.name)
        local added, changed = {}, {}
        for _, g in ipairs(m.goals) do
            if not old_g[key .. "\0" .. bare(g)] then
                if old_m[key] and old_s[key .. "\0" .. shape(g)] then changed[#changed + 1] = g
                else added[#added + 1] = g end
            end
        end
        if #changed > 0 then
            local name = (m.name:gsub(", %d+ cycles? left", ""))
            parts[#parts + 1] = "Changed: " .. (name ~= "" and (name .. ": ") or "") .. table.concat(changed, ". ")
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
local settle_text, settle_polls = nil, 0   -- a changed list waiting to hold still
local loaded_at = -100                     -- os.clock() when a loading screen was last seen

local function poll()
    crumb.at("quest: poll")
    -- At the main menu the game is left: the next game loaded may be another
    -- save, and its objectives came out as "Done:" the old save's ones
    -- (Profile 03 to Profile 02, VM, 2026-10-15). It is read whole instead.
    -- Likewise between Q Trial sectors: the results screen said "Done:
    -- Leave Sector. Objective: Acquire at least 90 DURANIUM (10/90)" as the
    -- exit spent the duranium (VM, 2026-10-15).
    -- Not the loading screen: away missions show it too, and every
    -- objective change after one read the whole list again (VM, 2026-10-15).
    -- Game Over too: its Reload Save loads without the main menu, and "New
    -- mission" over Game Over then "Mission ended" after the reload were
    -- said (VM, 2026-10-15).
    -- And the profile's save window (Continue, Load Autosave), which both
    -- games show before a load: the demo's objective was not read after
    -- loading (VM, 2026-10-16).
    for _, cls in ipairs({ "WBP_MainMenu_C", "WBP_SandboxSectorResult_C", "WBP_GameOver_C",
            "WBP_LoadSectorSaveWindow_C" }) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then
                last_missions = nil
                -- And the objective itself, so a save loaded from here is
                -- read once even when it is the one just left (nothing was
                -- said after the wait for the list to fill, 2026-10-15).
                last = nil
                -- And quiet for a while after it closes: between Reload
                -- Save and the loading screen the lost game's missions were
                -- read again, and the save then came out as "Done: Accept
                -- COMMS request. Missions ended: ..." (VM, 2026-10-17).
                loaded_at = os.clock() + 8
                return
            end
        end
    end
    -- During a conversation or a battle the main mission's line is gone
    -- while the game moves to its next objective: "Mission ended: Maneuvers"
    -- was said as the Kazon battle began, and "New mission: Maneuvers" after
    -- it (Casey's machine, 2026-10-15). The change is said once both are over.
    -- A loaded save's missions arrive one at a time for a few seconds: the
    -- two-poll wait alone still gave "Objective: Maneuvers" and then "New
    -- mission" for the rest (VM, 2026-10-15). Nothing is said until four
    -- seconds after the loading screen.
    for _, w in ipairs(FindAllOf("WBP_Loading_Screen_C") or {}) do
        if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then
            loaded_at = os.clock()
        end
    end
    if os.clock() - loaded_at < 4 then return end
    local okd, talking = pcall(function() return require("dialogue").active() ~= nil end)
    if (okd and talking) or require("combat").screen_up() then return end
    -- Nor over a cutscene or Q's voiced story: "Objective: The Long Way
    -- Home" talked over Q opening a Q Trial (Casey, 2026-10-15).
    local okc, scene = pcall(function()
        return require("dialogue").cutscene_playing() or require("story").active()
    end)
    if okc and scene then return end
    local now, missions = M.objective()
    -- A side mission's countdown changes every cycle; only a change in
    -- the objectives themselves is announced (VM, 2026-10-14). Progress
    -- counts too: "Store DEUTERIUM (552/900)" drops every cycle as fuel
    -- burns, and the objective was read four times in one trip (VM,
    -- 2026-10-15). O reads the current counts.
    -- The list fills in over a second or two after a load: "Objective:
    -- Maneuvers" came alone, then "New mission: Faces. New mission: Hull
    -- Integrity Low..." for missions that were there all along (VM,
    -- 2026-10-15). A change is said once the list has held for two polls.
    if now and (not last or bare(now) ~= bare(last)) then
        if bare(now) ~= settle_text then
            settle_text, settle_polls = bare(now), 1
            return
        end
        settle_polls = settle_polls + 1
        if settle_polls < 2 then return end
    end
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
