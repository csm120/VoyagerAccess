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

function M.say(text, interrupt)
    if type(text) ~= "string" then return end
    text = text:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    if interrupt and os.time() < hold_until then interrupt = false end
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
function M.say_long(text)
    if type(text) ~= "string" or text == "" then return end
    local _, words = text:gsub("%S+", "")
    M.say(text, false)
    hold_until = math.max(hold_until, os.time() + math.min(30, math.ceil(words / 3)))
end

-- Any key Casey presses ends a hold: he has chosen to move on.
function M.release()
    hold_until = 0
end

-- Asks the helper for a real left click at screen pixel (x, y).
function M.click(x, y)
    write("a", string.format("C|%.0f,%.0f\n", x, y))
end

return M
