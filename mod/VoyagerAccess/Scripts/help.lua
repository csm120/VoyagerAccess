-- F1: the keys for the screen Casey is on. F1 is unused by the game
-- (the game's own key bindings). The "Press F1 for help" hint on each new kind
-- of screen was removed (Casey, 2026-10-11): it came back on every screen
-- after each mod reload and update.

local speech = require("speech")

local M = {}

-- Only the keys that work on the screen you are on (Casey, 2026-10-11:
-- F1 said too much; the general keys came after every screen's own).
local HELP = {
    cutscene = "Shift+Enter skips the cutscene.",
    dialogue = "Enter continues. Shift+Enter skips to the choices. R repeats the last line. "
        .. "On choices, Up and Down move and Enter picks one.",
    ship = "Up and Down change deck. Left and Right move along the deck. Home and End go to the ends of the deck. "
        .. "Enter opens the room. V switches to the System Map. L says where you are.",
    system = "Up and Down move through the points of interest. Home and End go to the nearest and the farthest. "
        .. "Enter opens Scan and Set course. Backspace closes that list. V switches to the ship.",
    room = "Up and Down move between the buttons. Enter uses one. Left and Right switch tabs. Escape closes the room.",
    event = "Up and Down move between the options. Enter picks one. R reads the locked options.",
    mission = "Up and Down move through the choices, their heroes and Confirm. Home and End go to the first and last. "
        .. "Enter picks a hero or confirms. After a result, Enter continues and R repeats it.",
    settings = "Up and Down move between settings. Left and Right change the value. "
        .. "Home and End go to the first and last. Backspace goes back.",
    menu = "Up and Down move. Home and End go to the first and last. Enter selects. Backspace goes back.",
    none = "O reads your objective. C reads your resources. V switches between the ship and the System Map. "
        .. "L says where you are. R repeats the last line.",
}

-- Which kind of screen is in front, most specific first.
function M.context()
    local dialogue = require("dialogue")
    if dialogue.cutscene_playing() then return "cutscene" end
    if dialogue.active() then return "dialogue" end
    -- Event and room windows (2026-10-11): Escape closing a room is the
    -- game's own, tried with a real key press.
    local screen = require("screen")
    for _, pair in ipairs({ { "WBP_POIMultipleChoice_C", "event" }, { "WBP_RoomManagementV2_C", "room" } }) do
        for _, w in ipairs(FindAllOf(pair[1]) or {}) do
            if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(w) then
                return pair[2]
            end
        end
    end
    local focus = require("focus").context()
    if require("ship").active() and not focus then return "ship" end
    if require("system").active() and not focus then return "system" end
    return focus or "none"
end

function M.say_help()
    local ctx = require("awaymission").mission_active() and "mission" or M.context()
    speech.say(HELP[ctx] or HELP.none, true)
end

-- L: where am I. The kind of screen and what is selected on it, read the
-- way the arrows read it (Casey, 2026-10-11: after entering a room or
-- restarting you do not know where you are). Not Shift+Up: the game also
-- gets the arrow and would move focus. L is unbound in every context
-- (the game's own key bindings).
local PLACES = { cutscene = "Cutscene", dialogue = "Dialogue", ship = "Ship view", system = "System map",
    room = "Room window", event = "Point of interest", settings = "Settings", menu = "Menu", none = "Game" }

function M.say_where()
    local away = require("awaymission")
    local parts = {}
    if away.mission_active() then
        parts[1] = "Away mission"
        parts[2] = away.mission_where()
    else
        local ctx = M.context()
        parts[1] = PLACES[ctx] or "Game"
        if ctx == "room" then
            for _, w in ipairs(FindAllOf("WBP_RoomManagementV2_C") or {}) do
                if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and require("screen").shown(w) then
                    local head = require("rooms").window_text(w:GetFullName():match("^%S+%s+(.+)$"))
                    parts[1] = head:match("^[^%.]+") or parts[1]
                end
            end
            parts[2] = require("focus").current_label()
        elseif ctx == "ship" then
            parts[2] = require("ship").where() or "no room selected"
        elseif ctx == "system" then
            parts[2] = require("system").where() or "nothing selected"
        elseif ctx == "dialogue" or ctx == "cutscene" then
            parts[2] = nil
        else
            parts[2] = require("focus").current_label()
        end
    end
    local out = {}
    for _, p in ipairs(parts) do
        if p and p ~= "" then out[#out + 1] = (p:gsub("%.%s*$", "")) end
    end
    local text = table.concat(out, ". ") .. "."
    print("[VoyagerAccess] where: " .. text .. "\n")
    speech.say(text, true)
end

-- Entering and leaving a room window (Casey, 2026-10-11): the first room
-- window ever opened says once that Escape closes it (kept in a file, so
-- reloads and updates do not repeat it; the old per-screen F1 hint came
-- back after every reload), and closing one says where you are again.
local HINT_FILE = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\hint-room-escape"
local room_was_open = false
local back_to_ship = 0    -- polls left to wait for the ship view after a room closes

local function room_poll()
    local open = require("rooms").window_open()
    if open and not room_was_open then
        local f = io.open(HINT_FILE, "r")
        if f then
            f:close()
        else
            speech.say("Escape closes the room. F1 lists the keys.", false)
            local w = io.open(HINT_FILE, "w")
            if w then w:write("heard\n") w:close() end
        end
    elseif room_was_open and not open then
        back_to_ship = 10
    end
    room_was_open = open
    if back_to_ship > 0 then
        back_to_ship = back_to_ship - 1
        if require("ship").active() then
            back_to_ship = 0
            local here = require("ship").where()
            speech.say("Ship view" .. (here and (". " .. here) or ""), true)
        end
    end
end

function M.install()
    require("keys").on("f1", M.say_help)
    require("keys").on("l", M.say_where)
    LoopInGameThreadWithDelay(300, function()
        local ok, err = pcall(room_poll)
        if not ok then print("[VoyagerAccess] room poll error: " .. tostring(err) .. "\n") end
    end)
end

return M
