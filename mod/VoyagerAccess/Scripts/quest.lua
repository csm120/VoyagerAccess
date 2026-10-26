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
        return require("text").title(s)
    end))
end

-- "State of Flux: Visit the Class L Planet to search for FOOD. Pursuit of
-- Happiness, 29 cycles left: Gain +5 MORALE for 15 CYCLES (0/15)", or nil.
-- Each mission with its own objectives: they were all read under the main
-- mission's name, so a side mission's goal sounded like part of the story
-- (full game, VM, 2026-10-14). An objective's parent is its mission's
-- QuestRoot; the main mission (MainQuestLineDisplayWidget) comes first.
-- A tracker widget's text, from its own parts (screen.texts_in), cleaned as
-- popups.lua cleans window text: not popups.text_under, which searched every
-- text in the game for each widget (about 480 ms a reading, timing log,
-- 2026-10-21).
local function text_of_widget(w, skip)
    local out, seen = {}, {}
    for _, s in ipairs(screen.texts_in(w, skip)) do
        local t = popups.plain(s)
        if t ~= "" and t:sub(1, 1) ~= "#" and not seen[t] then
            seen[t] = true
            out[#out + 1] = t
        end
    end
    return table.concat(out, ". ")
end

-- A mission's name and countdown, from the line's own fields
-- (USTVQuestLineDisplayWidget.QuestLineText, WBP_QuestLineDisplay.CurrentCycle
-- while its CycleCounter is shown). Read from all of the line's texts in
-- their order it came out "Deuterium wird knapp. 15: ...", the number with
-- no word (firefly82, 2026-10-21). The texts are the fallback.
local function line_name(w)
    local name = ""
    pcall(function()
        local t = w.QuestLineText
        if t and t:IsValid() then name = popups.plain(t:GetText():ToString()) end
    end)
    if name == "" then return quest_name(text_of_widget(w, "WBP_QuestDisplay_C")) end
    local n = nil
    pcall(function()
        local c = w.CurrentCycle
        if c and c:IsValid() and screen.shown(c) then n = tonumber(c:GetText():ToString()) end
    end)
    if n then name = name .. ", " .. n .. (n == 1 and " cycle left" or " cycles left") end
    return name
end

function M.objective()
    local lines = {}
    for _, w in ipairs(FindAllOf("WBP_QuestLineDisplay_C") or {}) do
        local path = w:IsValid() and w:GetFullName():match("^%S+%s+(.+)$")
        if path and path:find("^/Engine/Transient%.") and screen.shown(w) then
            -- The line's own texts (name, cycles left), not its goals'.
            local line = { path = path .. ".", name = line_name(w), goals = {} }
            if path:find("MainQuestLineDisplayWidget", 1, true) then table.insert(lines, 1, line)
            else lines[#lines + 1] = line end
        end
    end
    local loose = {}
    for _, w in ipairs(FindAllOf("WBP_QuestDisplay_C") or {}) do
        local path = w:IsValid() and w:GetFullName():match("^%S+%s+(.+)$")
        if path and path:find("^/Engine/Transient%.") and screen.shown(w) then
            local t = text_of_widget(w):gsub("%s*%.%s*$", "")
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
    local lost_in = {}   -- missions that lost a goal in this change
    for _, m in ipairs(old) do
        local key = bare(m.name)
        if not new_m[key] then
            ended[#ended + 1] = m.name ~= "" and m.name:gsub(", %d+ cycles? left", "") or table.concat(m.goals, ". ")
        else
            for _, g in ipairs(m.goals) do
                if not new_g[key .. "\0" .. bare(g)] and not new_s[key .. "\0" .. shape(g)] then
                    done[#done + 1] = (g:gsub("%s*%([%d,]+/[%d,]+%)", ""))
                    lost_in[key] = true
                end
            end
        end
    end
    local back = false
    local now = os.clock()
    -- Or when a room has just got worse: switching the Holodeck, or its
    -- deck's Life Support, off minutes after the training began brought back
    -- "You need an active HOLO DECK" and the training was said as "Done"
    -- (Dark Frontier, VM, 2026-10-22; the 20 s rule missed it, and after a
    -- reload the requirement had never been seen done). A goal that finishes
    -- by itself, like a research, comes with no room getting worse. look()
    -- waits 300 ms first, as the room's change can come after the tracker's.
    local okr, lost_at = pcall(function() return require("ship").state_lost_at end)
    local room_lost = okr and type(lost_at) == "number" and math.abs(now - lost_at) < 2
    for _, m in ipairs(new) do
        local key = bare(m.name)
        for _, g in ipairs(m.goals) do
            local t = recent_done[bare(g)]
            -- Within seconds only: "Accept COMMS request" comes back as the
            -- next step after real progress all the time, and the research
            -- that finished just before it was said as "On hold" (Endgame,
            -- VM, 2026-10-19). The Holodeck flip-flop is a power toggle away.
            if not old_g[key .. "\0" .. bare(g)] and t and now - t < 20 then back = true end
            -- Only where the mission that lost a goal gained one in its place
            -- (the requirement back): a research finishing as some room went
            -- off is still done (Fable review, 2026-10-22).
            if room_lost and lost_in[key] and not old_g[key .. "\0" .. bare(g)] and not old_s[key .. "\0" .. shape(g)] then
                back = true
            end
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
-- A load is under way (the main menu, Game Over, a sector result or the
-- save window was up): the next reading is the whole list, not changes.
local fresh_load = false

-- Read when the game changes the quest tracker, not every second: the
-- 1 s loop read every objective by searching all texts in the game and
-- held the game about 480 ms each time (timing log, 2026-10-21; the cause
-- of most swallowed keys). The tracker's own calls (CXX/UHT dump):
-- STVQuestTrackerWidget:UpdateQuestLine (its event bus listener), and on
-- each mission line and goal OnAddedDisplayedQuest, OnUpdateDisplayedQuest,
-- UpdateQuestTracker, DisplayQuest_BP(Text) and OnUpdateValues(Current,
-- Target). OPEN POINT: which of them come, and in what order while a save
-- loads, is still to be seen in the game (Audit-Restschleifen.md, probe D).
-- Gone with the loop: the 4 s and 8 s quiet after a load and the "list
-- held for two polls" wait. A load now reads the whole list at its first
-- change after the loading screen.
local relook_pending = false
local function look()
    crumb.at("quest: look")
    -- At the main menu the game is left: the next game loaded may be another
    -- save, and its objectives came out as "Done:" the old save's ones
    -- (Profile 03 to Profile 02, VM, 2026-10-15). It is read whole instead.
    -- Likewise between Q Trial sectors, Game Over (Reload Save loads without
    -- the main menu) and the profile's save window (VM, 2026-10-15 and 16).
    -- popups.lua knows which windows are open.
    local loading, leaving = false, false
    for _, p in ipairs(popups.open_windows()) do
        if p:find("WBP_SandboxSectorResult_C", 1, true) or p:find("WBP_GameOver_C", 1, true)
            or p:find("WBP_LoadSectorSaveWindow_C", 1, true) then
            fresh_load = true
            leaving = true
        end
        if p:find("WBP_Loading_Screen_C", 1, true) then loading = true end
    end
    if fresh_load then last_missions, last = nil, nil end
    -- Nothing is read while one of those windows is up: the list behind
    -- Game Over would be read, fresh_load cleared, and the reload compared
    -- with the lost game ("Done: Accept COMMS request", 2026-10-15; 0.3.67
    -- returned here; review of firefly82's patch, 2026-10-21). Its close
    -- asks for a look (popups.on_close below).
    if leaving then return end
    -- During a conversation or a battle the main mission's line is gone
    -- while the game moves to its next objective: "Mission ended: Maneuvers"
    -- was said as the Kazon battle began, and "New mission: Maneuvers" after
    -- it (Casey's machine, 2026-10-15). The change is said once both are
    -- over: the next look after them (the tracker changes again then).
    -- Looked at again a second later while the loading screen is up: the
    -- tracker's events came during the load and nothing asked again after
    -- it, so a loaded save never said its objective (VM, 2026-10-21, the
    -- event version). Only while loading; a quick check each time.
    if loading then
        ExecuteInGameThreadWithDelay(1000, function() M.request_look() end)
        return
    end
    local okd, talking = pcall(function() return require("dialogue").active() ~= nil end)
    -- Nor over a cutscene or Q's voiced story: "Objective: The Long Way
    -- Home" talked over Q opening a Q Trial (Casey, 2026-10-15).
    local okc, scene = pcall(function()
        return require("dialogue").cutscene_playing() or require("story").active()
    end)
    if (okd and talking) or require("combat").screen_up() or (okc and scene) then
        -- Looked at again once it is over: a goal that changed during a
        -- conversation ("One Small Step: Craft Shuttle Shield Adjustments")
        -- was never said, as the tracker did not change again after it (VM,
        -- 2026-10-22). One retry pending at a time, a second apart.
        if not relook_pending then
            relook_pending = true
            ExecuteInGameThreadWithDelay(1000, function()
                relook_pending = false
                M.request_look()
            end)
        end
        return
    end
    local now, missions = M.objective()
    -- A side mission's countdown changes every cycle; only a change in the
    -- objectives themselves is announced (VM, 2026-10-14). Progress counts
    -- too: "Store DEUTERIUM (552/900)" drops every cycle as fuel burns, and
    -- the objective was read four times in one trip (VM, 2026-10-15). O
    -- reads the current counts.
    if now and (not last or bare(now) ~= bare(last)) then
        print("[VoyagerAccess] objective: " .. now .. "\n")
        -- After the first reading, only what changed is said; the whole
        -- list is the first reading (and after a reload) and O.
        local before = last_missions
        local said_now = now
        ExecuteInGameThreadWithDelay(300, function()
            local okc, change = pcall(function() return before and M.changes(before, missions) end)
            speech.say((okc and change) or ("Objective: " .. said_now), false)
        end)
        last = now
        write_last(now)
    end
    if now then
        last_missions = missions
        fresh_load = false
    end
end

local queued = false
-- After a load the missions arrive one tracker event at a time, so the
-- first look read part of the list and the rest came as "New mission: ..."
-- or "Done: Accept COMMS request" (2026-10-15 and 17, back with the event
-- version; review of firefly82's patch, 2026-10-21). While a load is under
-- way the look waits until the tracker has been quiet for LOAD_SETTLE_MS;
-- each new event starts the wait again. Not a loop.
local LOAD_SETTLE_MS = 1500
local settle_token = 0
function M.request_look()
    if fresh_load then
        settle_token = settle_token + 1
        local mine = settle_token
        ExecuteInGameThreadWithDelay(LOAD_SETTLE_MS, function()
            if settle_token ~= mine then return end
            local ok, err = pcall(look)
            if not ok then print("[VoyagerAccess] quest error: " .. tostring(err) .. "\n") end
        end)
        return
    end
    if queued then return end
    queued = true
    ExecuteInGameThread(function()
        queued = false
        local ok, err = pcall(look)
        if not ok then print("[VoyagerAccess] quest error: " .. tostring(err) .. "\n") end
    end)
end

local hooked = {}
local function hook_widget(path, names)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return end
    local cpath = w:GetClass():GetFullName():match("^%S+%s+(.+)$")
    if not cpath or hooked[cpath] then return end
    hooked[cpath] = true
    local got = {}
    for _, fn in ipairs(names) do
        if StaticFindObject(cpath .. ":" .. fn) and pcall(RegisterHook, cpath .. ":" .. fn, function() M.request_look() end) then
            got[#got + 1] = fn
        end
    end
    print("[VoyagerAccess] quest: " .. cpath:match("([%w_]+)$") .. " events: " .. table.concat(got, ", ") .. "\n")
    M.request_look()
end

function M.install()
    require("keys").on("o", M.say_objective)
    local okh = pcall(RegisterHook, "/Script/STVoyager.STVQuestTrackerWidget:UpdateQuestLine", function() M.request_look() end)
    print("[VoyagerAccess] quest: tracker event " .. (okh and "hooked" or "not hooked") .. "\n")
    -- A battle's end from the game's event bus (firefly82's census, 26
    -- October): the objectives held back during the battle are looked at
    -- then. The one-second retry while the battle screen is up stays as the
    -- fallback (the screen can still be up at this event; logged to see).
    local okc = pcall(RegisterHook, "/Script/STVoyager.STVSectorSummarySubsystem:OnCombatFinished", function()
        ExecuteInGameThread(function()
            local up = false
            pcall(function() up = require("combat").screen_up() and true or false end)
            print("[VoyagerAccess] quest: combat finished, battle screen up: " .. tostring(up) .. "\n")
            M.request_look()
        end)
    end)
    print("[VoyagerAccess] quest: combat finished event " .. (okc and "hooked" or "not hooked") .. "\n")
    local LINE = { "OnAddedDisplayedQuest", "OnUpdateDisplayedQuest", "UpdateQuestTracker" }
    local GOAL = { "DisplayQuest_BP", "OnUpdateValues" }
    popups.on_widget("WBP_QuestLineDisplay_C", function(p) hook_widget(p, LINE) end)
    popups.on_widget("WBP_QuestDisplay_C", function(p) hook_widget(p, GOAL) end)
    -- The main menu: a load is coming.
    popups.on_widget("WBP_MainMenu_C", function() fresh_load = true end)
    -- Likewise a Q Trial sector's results, Game Over and the save window,
    -- when one is read: look() only saw them if a tracker event came while
    -- they were open, and after a Q Trial sector change the old sector's
    -- goals were said as "Missions ended: Scientific Survey, Krowtonan
    -- Guard" instead of the new list (VM, 2026-10-21). On reading, not on
    -- the game making the widget, which it may do without showing it.
    local LEAVING = { WBP_SandboxSectorResult_C = true, WBP_GameOver_C = true, WBP_LoadSectorSaveWindow_C = true }
    popups.on_read(function(_, cls) if LEAVING[cls] then fresh_load = true end end)
    for cls, names in pairs({ WBP_QuestLineDisplay_C = LINE, WBP_QuestDisplay_C = GOAL }) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            local p = w:IsValid() and w:GetFullName():match("^%S+%s+(.+)$")
            if p and p:find("^/Engine/Transient%.") then pcall(hook_widget, p, names) break end
        end
    end
    -- After a loading screen and after dialogue or battle, the tracker may
    -- not change again: a window closing (popups.lua) asks for a look too.
    popups.on_close(function() M.request_look() end)
end

return M
