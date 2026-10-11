-- F1: the keys for the screen Casey is on. The first time each kind of
-- screen comes up in a session, "Press F1 for help" is said once (Casey,
-- 2026-10-10: "switch the power on" did not say how). F1 is unused by the
-- game (the game's own key bindings).

local speech = require("speech")
local crumb = require("crumb")

local M = {}

local INTERVAL_MS = 500

local HELP = {
    cutscene = "Cutscene. Shift+Enter skips it.",
    dialogue = "Dialogue. Enter continues. Shift+Enter skips ahead to the next choice. "
        .. "R repeats the last line. When choices appear, Up and Down Arrow move between them and Enter picks one.",
    ship = "Ship view. Up and Down Arrow change deck. Left and Right Arrow move between the rooms on a deck. "
        .. "Home and End go to the first and last room on the deck. Enter opens the selected room.",
    system = "System map. Up and Down Arrow move through the points of interest in this system, nearest first. "
        .. "Home and End go to the nearest and the farthest. Enter opens a list of actions for the selected one: "
        .. "Scan and Set course. Up and Down choose, Enter does it, Backspace closes the list.",
    room = "Room window. Up and Down Arrow move between its buttons, and each one says what it costs and why it "
        .. "cannot be used yet. Enter uses the selected one. Escape closes the room.",
    event = "Point of interest. Up and Down Arrow move between the options, and each one says its reward, its risk "
        .. "and its chances. Enter picks one. R reads the locked options.",
    settings = "Settings. Up and Down Arrow move between settings. Home and End go to the first and last. "
        .. "Left and Right Arrow change the value. Backspace goes back.",
    menu = "Menu. Up and Down Arrow move between items. Home and End go to the first and last. Enter selects. "
        .. "Backspace goes back.",
    none = "O reads your objective. C reads your resources. V switches between the ship and the System Map. "
        .. "R repeats the last line or tutorial.",
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
    local ctx = M.context()
    speech.say(HELP[ctx] .. (ctx ~= "none" and " " .. HELP.none or ""), true)
end

local hinted = { none = true }
local last = nil

local function poll()
    crumb.at("help: poll")
    local ctx = M.context()
    if ctx ~= last and not hinted[ctx] then
        hinted[ctx] = true
        speech.say("Press F1 for help.", false)
    end
    last = ctx
end

function M.install()
    require("keys").on("f1", M.say_help)
    LoopInGameThreadWithDelay(INTERVAL_MS, function()
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] help error: " .. tostring(err) .. "\n") end
    end)
end

return M
