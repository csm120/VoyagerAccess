-- Hands text to tools/speech_helper.py through a file it tails.
-- One line per message: "I|text" interrupts, "Q|text" queues.
-- If the folder is missing (helper never run), messages are dropped; the first failure is logged.

local M = {}

local PATH = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\speech.txt"

-- A write that fails is logged once per session, so UE4SS.log says why a
-- player heard nothing (2026-10-29: every failure was dropped silently).
local write_failed = false
local function write(mode, line)
    local f, err = io.open(PATH, mode)
    if not f then
        if not write_failed then
            write_failed = true
            print("[VoyagerAccess] speech.txt could not be written: " .. tostring(err) .. "\n")
        end
        return false
    end
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
-- What the mod said by itself (queued, or a window read; not a key's own
-- answer) is held until about when it has been said, at 14 characters a
-- second, and a key ends that: an interrupting line in that time queues.
-- Casey's log of 2026-10-26 had nine lines cut off with no key pressed:
-- "Done: ... Objective: ..." by the view line after a conversation, a scan
-- result by a hail, "Arrived at" by the event window. in_story and in_long:
-- say_story or say_long is speaking now (os.clock, seconds).
local self_until, in_story, in_long = 0, false, false
-- The lines said by themselves in the last 1.5 s, { at, text }
-- (say_protected); in_protected: say_protected is speaking now;
-- released_at: the last key (release).
local self_lines, in_protected, released_at = {}, false, -100
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

-- built: the line already has the mod's own words in the game's language
-- (tr.fill and tr.word where it was made), around the game's own texts. The
-- line pass (tr.apply) is skipped then: it runs every one of the table's
-- phrases over the line, 36 to 77 ms for one new tech tree line (timing
-- log, 2026-10-24), and over the game's texts as well, which it can change
-- (German "die Betrieb" for the game's "die Operation", 2026-10-24).
function M.say(text, interrupt, built)
    if type(text) ~= "string" then return end
    local asked = interrupt
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
    text = text:gsub("%s+&%s+", " " .. require("tr").word("and") .. " ")
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
    -- Every form the game's own texts put before a species number, taken
    -- from its language files (2026-10-20): Spanish Especie, Polish
    -- Gatunek/Gatunku/Gatunkowi/Gatunkiem, Russian вид/вида/виду/виде/видом
    -- (sometimes with a no-break space), Japanese 生命体 with no space.
    -- Chinese puts no word right before the number.
    local SPECIES = { "[Ss]pecies", "[Ss]pezies", "[Ee]sp\195\168ce", "[Ee]specie", "[Gg]atun%l*",
        "\208[\146\178]\208\184\208\180", "\208[\146\178]\208\184\208\180\208\176", "\208[\146\178]\208\184\208\180\209\131",
        "\208[\146\178]\208\184\208\180\208\181", "\208[\146\178]\208\184\208\180\208\190\208\188" }
    for _, word in ipairs(SPECIES) do
        text = text:gsub("(" .. word .. "[%s\194\160]+)(%d+)", function(w, d) return w .. spaced(d) end)
    end
    text = text:gsub("(\231\148\159\229\145\189\228\189\147)(%d+)", function(w, d) return w .. spaced(d) end)
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
    -- English only: in German it changed the game's own words ("Holo
    -- deck", "Aero shuttle-Rampe"; firefly82's review, 2026-10-20).
    local okl, lang = pcall(require, "language")
    if not (okl and lang and lang.english) or lang.english() then
        text = split_words(text)
    elseif not built then
        -- The mod's own words in the game's language (tr.lua).
        local okt, tr = pcall(require, "tr")
        if okt and tr then
            local oka, out = pcall(tr.apply, text)
            if oka and type(out) == "string" then text = out end
        end
    end
    if text == "" then return end
    -- Development sweep for labels with no words (unread.lua).
    local unread = package.loaded["unread"]
    if unread and unread.on then pcall(unread.check_spoken, text) end
    -- A key's answer can come up to a few hundred ms after the key (combat
    -- energy, 60 to 300 ms): within 0.6 s of the key it is not held back by
    -- something said by itself in between (GPT review, 2026-10-26).
    local key_answer = interrupt and os.clock() - released_at < 0.6
    if interrupt and (os.time() < hold_until or os.time() < protect_until
        or (os.clock() < self_until and not key_answer)) then interrupt = false end
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
    -- Only what came by itself (sent queued, or a window read): a key's own
    -- answer, said with interrupt, is cut by the next line as before. A
    -- line asked to interrupt but queued here came by itself too (a view
    -- line, a conversation line behind a scan result).
    if not interrupt or in_long then
        local now = os.clock()
        self_until = math.max(self_until, now) + #text / 14
        if not in_protected then
            -- The last 1.5 s only, line by line: an hour with no key would
            -- otherwise keep every line.
            local kept = {}
            for _, l in ipairs(self_lines) do
                if now - l.at < 1.5 then kept[#kept + 1] = l end
            end
            kept[#kept + 1] = { at = now, text = text }
            self_lines = kept
        end
    end
    write("a", (interrupt and "I|" or "Q|") .. text .. "\n")
end

-- A conversation line interrupts the line before it, but not what the mod
-- said by itself that is still being said (self_until): a hail right after
-- a scan cut off its result ("Shipwreck. System. 9,840.0", "Resources.
-- Deuterium. unknown", "Found Deuterium", then "Tom Paris: Let's grab the
-- deuterium then"; Casey's speech.txt, 2026-10-26). It queues behind it.
function M.say_story(text)
    hold_until = 0
    in_story = true
    pcall(M.say, text, true)
    in_story = false
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
    in_long = true
    pcall(M.say, text, interrupt == true)
    in_long = false
    hold_until = math.max(hold_until, os.time() + math.min(30, math.ceil(words / 3)))
end

-- A tutorial: queued after what is speaking, and nothing interrupts it
-- until a key is pressed. A time estimate cannot know how fast a screen
-- reader speaks, and tutorials close themselves (firefly82, 2026-10-18), so
-- what comes after it queues behind it instead; ten minutes is only a cap.
-- But a tutorial that opens over a window just read (within 1.5 s, no key
-- between) is said first and the window's lines again after it, as a
-- sighted player sees the tutorial in front: the Transporter Room tutorial
-- came 15 s late, after the whole away briefing, and held the keys
-- meanwhile (Casey's NVDA log, 2026-10-26). Its title and text come in one
-- tick, so the window's lines follow on the next.
-- Not while an earlier tutorial is still protected: it stays first.
local requeue, requeue_gen = nil, 0
function M.say_protected(text)
    if type(text) ~= "string" or text == "" then return end
    local recent = false
    for _, l in ipairs(self_lines) do
        if os.clock() - l.at < 1.5 then recent = true end
    end
    local first = not requeue and recent and os.time() >= protect_until
    in_protected = true
    if first then
        requeue = self_lines
        self_lines = {}
        hold_until, self_until = 0, 0
        pcall(M.say, text, true)
        local gen = requeue_gen
        ExecuteInGameThread(function()
            -- A key in between (release) drops the lines: the player has
            -- moved on, and the window may be gone.
            if gen ~= requeue_gen then return end
            local again = requeue or {}
            requeue = nil
            for _, l in ipairs(again) do write("a", "Q|" .. l.text .. "\n") end
        end)
    else
        pcall(M.say, text, false)
    end
    in_protected = false
    protect_until = math.max(protect_until, os.time() + 600)
end

-- Any key Casey presses ends a hold: he has chosen to move on.
function M.release()
    hold_until = 0
    protect_until = 0
    self_until = 0
    self_lines = {}
    requeue, requeue_gen = nil, requeue_gen + 1
    released_at = os.clock()
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
