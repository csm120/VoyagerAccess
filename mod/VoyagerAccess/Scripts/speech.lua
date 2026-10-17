-- Hands text to tools/speech_helper.py through a file it tails.
-- One line per message: "I|text" interrupts, "Q|text" queues.
-- If the folder is missing (helper never run), messages are dropped quietly.

local M = {}

local PATH = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\speech.txt"

local function write(mode, line)
    local f = io.open(PATH, mode)
    if not f then return false end
    f:write(line)
    f:close()
    return true
end

-- Empties the file so it does not grow across sessions.
function M.reset()
    write("w", "")
end

-- Story text (dialogue lines, story cards) must not be cut off by the focus
-- announcement that arrives a moment later ("Continue" cut off the "Into the
-- Badlands" card). For HOLD_SECONDS after say_story, an interrupting say is
-- queued instead. os.time has 1 s resolution, so the hold is 1 to 2 s.
local HOLD_SECONDS = 2
local hold_until = 0
-- A tutorial is protected for as long as it takes to say, and only a key
-- press ends that: a window opening just after (an event, a report) is
-- read with interrupt and cleared the ordinary hold, so the tutorial was
-- cut off, and tutorials close themselves (forum player, 2026-10-16).
local protect_until = 0
local last_text, last_at = nil, -100

-- Words the game writes run together, which some synthesizers say as one
-- mushed word ("Shuttlebay", "Lifesupport"; Casey, 2026-10-15). The number
-- is where the space goes. Found in the game's own text; everyday words
-- such as "starship" and "subspace" are left alone.
local SPLIT = { shuttlebay = 7, aeroshuttlebay = 4, aeroshuttle = 4, aerowing = 4, sickbay = 4, holodeck = 4,
    turbolift = 5, transwarp = 5, nanoprobe = 4, lifeform = 4, lifesign = 4, lifesupport = 4, warpcore = 4,
    messhall = 4, shuttlecraft = 7, stardate = 4, homeworld = 4 }
local function split_words(text)
    return (text:gsub("%a+", function(w)
        local l = w:lower()
        local base, tail = l, ""
        if not SPLIT[base] and l:sub(-1) == "s" then base, tail = l:sub(1, -2), "s" end
        local at = SPLIT[base]
        if not at then return nil end
        local out = w:sub(1, at) .. " " .. w:sub(at + 1)
        -- Aeroshuttlebay: "Aero shuttlebay", then the rest.
        if base == "aeroshuttlebay" then out = w:sub(1, 4) .. " " .. w:sub(5, 11) .. " " .. w:sub(12) end
        return out
    end))
end

function M.say(text, interrupt)
    if type(text) ~= "string" then return end
    text = text:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    -- Parts joined with ". " after text that already ended a sentence read
    -- "two times).. With" and "Incoming!." (2026-10-14). Ellipses stay.
    text = (" " .. text .. " "):gsub("([^%.])%.%.([^%.])", "%1.%2"):gsub("([!?])%.(%s)", "%1%2"):gsub("%s+%.(%s)", ".%1"):gsub("%s+,", ","):gsub("%s+([;:!%?%)])", "%1")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    -- "Severely Injured & Sick" (Sickbay patients, VM, 2026-10-16): with
    -- punctuation off a screen reader may say nothing for the "&".
    text = text:gsub("%s+&%s+", " and ")
    -- Brackets round a name: "the [TECH TREE]" (room descriptions) and
    -- "[Sick bay] got damaged" (a sabotage toast), VM, 2026-10-16.
    -- Placeholders like "[{Shuttle}]" are left to their readers.
    text = text:gsub("%[([^%[%]{}]+)%]", "%1")
    text = split_words(text)
    if text == "" then return end
    if interrupt and (os.time() < hold_until or os.time() < protect_until) then interrupt = false end
    -- The same line queued again right after itself is dropped: the demo's
    -- first event option was read twice in a row (VM, 2026-10-15). A key
    -- press repeating a line interrupts, and is still said.
    if not interrupt and text == last_text and os.clock() - last_at < 2 then return end
    last_text, last_at = text, os.clock()
    write("a", (interrupt and "I|" or "Q|") .. text .. "\n")
end

function M.say_story(text)
    hold_until = 0
    M.say(text, true)
    hold_until = os.time() + HOLD_SECONDS
end

-- A window's text (an event, a tutorial) is held for about as long as it
-- takes to say, at roughly three words a second: the focus announcement of
-- the window's first option cut off an event's locked options
-- (2026-10-11). Queued after anything already speaking.
function M.say_long(text, interrupt)
    if type(text) ~= "string" or text == "" then return end
    local _, words = text:gsub("%S+", "")
    if interrupt then hold_until = 0 end
    M.say(text, interrupt == true)
    hold_until = math.max(hold_until, os.time() + math.min(30, math.ceil(words / 3)))
end

-- A tutorial: queued after what is speaking, and nothing interrupts it
-- until it has had time to be said or a key is pressed.
function M.say_protected(text)
    if type(text) ~= "string" or text == "" then return end
    local _, words = text:gsub("%S+", "")
    M.say(text, false)
    protect_until = math.max(protect_until, os.time() + math.min(60, math.ceil(words / 3) + 1))
end

-- Any key Casey presses ends a hold: he has chosen to move on.
function M.release()
    hold_until = 0
    protect_until = 0
end

-- Asks the helper for a real left click at screen pixel (x, y).
-- The helper puts the mouse cursor in the middle of the game window.
function M.center_mouse()
    write("a", "M|center\n")
end

-- The helper puts the mouse cursor on a radial menu segment: x, y are the
-- segment's offset from the ring's centre in ring radii.
function M.ring_mouse(x, y)
    write("a", string.format("M|ring,%.3f,%.3f\n", x, y))
end

-- The same, then a real left click there (the helper's M|ringclick).
function M.ring_click(x, y)
    write("a", string.format("M|ringclick,%.3f,%.3f\n", x, y))
end

function M.click(x, y)
    write("a", string.format("C|%.0f,%.0f\n", x, y))
end

return M
