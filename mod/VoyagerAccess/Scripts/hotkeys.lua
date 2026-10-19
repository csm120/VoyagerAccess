-- Ctrl+F1: every key, as a list you can browse in the game (Casey,
-- 2026-10-14: "a complete hotkey list that we can browse through in game").
-- The same list as docs/keyboard.md, grouped by screen; the first item of
-- each group starts with the group's name. Up and Down move, Home and End go
-- to the ends, Enter repeats the item, Ctrl+F1 again, Backspace or Escape
-- close it. F1 alone still says only the keys for the screen you are on.

local speech = require("speech")

local M = {}

local GROUPS = {
    { "Everywhere", {
        "F1: the keys for the screen you are on",
        "Control F1: this list of every key. Escape or Backspace closes it",
        "I: where you are and what is selected",
        "O: your objective. In combat, the combat goal",
        "C: hull, resources, crew, energy, battery and morale, as a list. Enter on a line lists its details, as the game's tooltip shows them; Backspace goes back",
        "N: navigation list: ship view, System Map, Sector Map, Overview, Research, Wait one cycle",
        "V: switch between the ship view and the System Map",
        "R: repeat the last line, tutorial or card; R again within 5 seconds goes back through earlier messages",
        "Backtick, the key left of 1: copy a troubleshooting report to the clipboard",
        "F12: check for a Voyager Access update, or restart the game to install one",
        "Control F12: what's new in Voyager Access",
        "Escape: the game's back and pause menu. It also closes the mod's lists",
    } },
    { "Menus, lists and windows", {
        "Up and Down: move",
        "Home and End: first and last",
        "Enter: select",
        "Backspace: go back, or close a list the mod opened",
        "Left and Right: change a setting, or switch a window's tabs",
    } },
    { "Dialogue", {
        "Enter: continue",
        "Shift Enter: skip ahead to the choices. In a cutscene, skip it",
        "On choices, Up and Down move and Enter picks. A major decision is held for you",
    } },
    { "Ship view", {
        "Up and Down, or Page Up and Page Down: change deck",
        "Left and Right: move along the deck. Home and End: the ends of the deck",
        "Enter: open the room. On empty building space, the construction ring",
        "J: list of the ship's rooms with deck and state. Enter selects one, J or Backspace closes it",
        "I twice: the room's details as a list, as the game shows them when pointing at the room: level, energy, crew, and what E does and costs. Backspace or Escape closes it",
        "In a room window: Up and Down move between buttons, Left and Right switch tabs, Escape closes it",
        "In a ring of actions: Up and Down move, Enter picks, Escape closes it",
        "E, the game's key: the room's quick action, such as power on or off, repair, clear debris, or pause work. It acts on the room you last moved to",
        "F, the game's key: upgrade that room. T, the game's key: demolish that room",
    } },
    { "System Map and Sector Map", {
        "Up and Down: points of interest, or star systems on the Sector Map",
        "Home and End: the nearest and the farthest",
        "Enter: Scan and Set course. Backspace closes that list",
        "I: adds the trip's progress while Voyager is under way",
    } },
    { "Events at a point of interest", {
        "Up and Down: the options. R reads the locked ones",
        "Left and Right: choose a hero, where the option can take one",
        "Enter: pick the option, with the hero you chose",
    } },
    { "Tech tree", {
        "Up and Down: tiers, then technologies. Left and Right: switch category",
        "Enter: open the item's panel. Enter again begins the research. Escape closes the panel, then the tree",
    } },
    { "Away missions", {
        "Up and Down: the choices, their heroes and Confirm. Home and End: first and last",
        "Enter: pick a hero, or confirm",
        "After a result, Enter continues and R repeats it",
    } },
    { "Combat", {
        "Enter: open Orders. In the order wheel, Up and Down move, Enter picks, Back is last",
        "I: both ships, the enemies, the order, torpedoes, abilities and the goal",
        "O: the combat goal",
        "Space, the game's key: pause and resume",
        "1 to 3, the game's keys: the heroes' abilities",
        "Tab, the game's key: next target",
        "Shift, the game's key: fire a torpedo",
        "Left and Right, the game's keys: pick a system. Up and Down: move energy to it",
    } },
}

local function build()
    local items = {}
    for _, g in ipairs(GROUPS) do
        for i, text in ipairs(g[2]) do
            items[#items + 1] = (i == 1 and (g[1] .. ". ") or "") .. text
        end
    end
    return items
end

local items, index = nil, nil

local function say_item()
    speech.say(string.format("%s. %d of %d", items[index], index, #items), true)
end

function M.open()
    return items ~= nil
end

function M.toggle()
    if items then
        items = nil
        speech.say("Closed", true)
        return
    end
    items, index = build(), 1
    require("focus").park_focus()
    say_item()
end

function M.step(dir)
    if items[index + dir] then index = index + dir end
    say_item()
end

function M.edge(last)
    index = last and #items or 1
    say_item()
end

function M.repeat_item()
    say_item()
end

function M.close()
    if not items then return false end
    items = nil
    speech.say("Closed", true)
    return true
end

function M.install()
    require("keys").on("ctrl+f1", M.toggle)
end

return M
