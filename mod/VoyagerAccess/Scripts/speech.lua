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
    -- And after a quote that already ended its sentence: "enhancements.".
    -- (Combat Capabilities, Q Trial, VM, 2026-10-17).
    text = text:gsub('([%.!%?]")%.', "%1"):gsub("([%.!%?]\226\128\157)%.", "%1")
    -- "Severely Injured & Sick" (Sickbay patients, VM, 2026-10-16): with
    -- punctuation off a screen reader may say nothing for the "&".
    text = text:gsub("%s+&%s+", " and ")
    -- Species 8472 is said digit by digit, as the crew and the Borg say it,
    -- not "eight thousand four hundred..." (Casey, 2026-10-17).
    text = text:gsub("%f[%d]8472%f[%D]", "8 4 7 2")
    -- Every designation, digit by digit (Casey, 2026-10-18): "Species 116"
    -- is "Species 1 1 6", and registries such as "NX-01-A" or "NCC-74656"
    -- are read the same way.
    local function spaced(d) return (d:gsub("%d", "%0 "):gsub(" $", "")) end
    -- The word in the game's other languages too ("Spezies 116" was read
    -- as a number in German, firefly82's review, 2026-10-19): German
    -- Spezies, French espèce, Polish gatunek.
    for _, word in ipairs({ "[Ss]pecies", "[Ss]pezies", "[Ee]sp\195\168ce", "[Gg]atunek" }) do
        text = text:gsub("(" .. word .. "%s+)(%d+)", function(w, d) return w .. spaced(d) end)
    end
    text = text:gsub("%f[%w](%u%u%u?)%-(%d+)%-?(%u?)%f[%W]", function(p, d, l)
        return p .. " " .. spaced(d) .. (l ~= "" and (" " .. l) or "")
    end)
    -- French and other languages group thousands with a narrow or plain
    -- no-break space ("-1 170", U+202F or U+00A0), which a reader may say
    -- as two numbers (VM, French, 2026-10-17). Joined between digits.
    text = text:gsub("(%d)\226\128\175(%d)", "%1%2"):gsub("(%d)\194\160(%d)", "%1%2")
    -- 19 tech descriptions start "[NOT WORKING YET]" (text scan, 2026-10-15),
    -- which a synthesizer may spell out letter by letter.
    text = text:gsub("%[NOT WORKING YET%]%s*", "Not working yet: ")
    -- A placeholder the game left unfilled ("{AlliedShipÍnitialCost}", text
    -- scan) is dropped, and logged so new ones show up.
    text = text:gsub("{[^{}]+}", function(p)
        print("[VoyagerAccess] placeholder: " .. p .. "\n")
        return ""
    end):gsub("%[%s*%]", ""):gsub("%(%s*%)", ""):gsub("  +", " ")
    -- Brackets round a name: "the [TECH TREE]" (room descriptions) and
    -- "[Sick bay] got damaged" (a sabotage toast), VM, 2026-10-16.
    -- Placeholders like "[{Shuttle}]" are left to their readers.
    -- A bracket before a new sentence ends one: "[WARNING: You need 2 heroes
    -- for this away mission] Send away team" ran together (VM, 2026-10-17).
    text = text:gsub("%[([^%[%]{}]-[^%.!%?%[%]{}])%]%s+(%u)", "%1. %2")
    text = text:gsub("%[([^%[%]{}]+)%]", "%1")
    text = split_words(text)
    if text == "" then return end
    -- Development sweep for labels with no words (unread.lua).
    local unread = package.loaded["unread"]
    if unread and unread.on then pcall(unread.check_spoken, text) end
    if interrupt and (os.time() < hold_until or os.time() < protect_until) then interrupt = false end
    -- The same line queued again right after itself is dropped: the demo's
    -- first event option was read twice in a row (VM, 2026-10-15). A key
    -- press repeating a line interrupts, and is still said.
    if not interrupt and text == last_text and os.clock() - last_at < 2 then return end
    -- And a toast that repeats the end of the line just said: "Kathryn
    -- Janeway: Get started on that vaccine, Doctor. Anti-Radiation Vaccine
    -- unlocked in the Crew TECH TREE", then the toast alone (sector 8,
    -- 2026-10-18).
    if not interrupt and last_text and #text >= 12 and #last_text > #text and os.clock() - last_at < 3
        and last_text:sub(-#text) == text then return end
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
-- until a key is pressed. A time estimate cannot know how fast a screen
-- reader speaks, and tutorials close themselves (firefly82, 2026-10-18), so
-- what comes after it queues behind it instead; ten minutes is only a cap.
function M.say_protected(text)
    if type(text) ~= "string" or text == "" then return end
    M.say(text, false)
    protect_until = math.max(protect_until, os.time() + 600)
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
