-- V switches between the ship view and the System Map. The game has no
-- keyboard binding for it, only the Ship and System buttons in the HUD's
-- navigation bar (ShowShipButton, ShowSystemButton, found 2026-10-11);
-- until then only tutorials switched views for Casey. V is unbound.

local speech = require("speech")
local screen = require("screen")

local M = {}

local function find(name)
    for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
        local p = b:IsValid() and b:GetFullName():match("^%S+%s+(.+)$")
        if p and p:find("WBP_NavigationBar", 1, true) and p:find("%." .. name .. "$") and screen.shown(b) then
            return b
        end
    end
    return nil
end

function M.toggle()
    -- Not behind a window: V switched the map behind an open Research
    -- Report (VM, 2026-10-15).
    if require("focus").virtual_window_open() then
        speech.say("Close the window first", true)
        return
    end
    local to_map = require("ship").active()
    local b = find(to_map and "ShowSystemButton" or "ShowShipButton")
    if not b then
        speech.say("Cannot switch view here", true)
        return
    end
    b:HandleButtonPressed()
    b:HandleButtonReleased()
    b:HandleButtonClicked()
    -- help.lua says the new view and what is selected once it is up.
end

-- N: the navigation bar as a list (Casey, 2026-10-11: "how do I get to the
-- other tabs from ship view?"). The bar (WBP_NavigationBar) takes only the
-- mouse and is shown only in the ship and map views. Up and Down choose,
-- Enter presses, Backspace closes the list. N is unbound in the game.
local NAV = {
    { "Ship view", "ShowShipButton" }, { "System map", "ShowSystemButton" },
    { "Sector map", "ShowSectorButton" }, { "Overview", "OverviewButton" },
    { "Research", "ResearchButton" }, { "Wait one cycle", "WaitOneCycleButton" },
    { "Incoming calls", "IncomingCallsButton" }, { "Sector switch", "SectorSwitchButton" },
    -- Q Trials only: opens Leave Sector (missing from N, VM, 2026-10-14)
    { "Leave sector", "SandboxExitSector" },
}
local nav_items, nav_index = nil, nil

-- Only in the ship view and the System Map, where the bar lives: opened
-- over the game menu, Up and Down moved both the list and the menu, and the
-- two talked over each other (2026-10-11).
local function nav_place()
    local ctx = require("help").context()
    return ctx == "ship" or ctx == "system"
end

function M.nav_open()
    if nav_items and not nav_place() then nav_items = nil end
    return nav_items ~= nil
end

-- For I (where am I) while N is open: it described the map behind the
-- list (VM, 2026-10-14).
function M.nav_where()
    if not M.nav_open() then return nil end
    local it = nav_items[nav_index]
    if not it then return "Navigation list" end
    return string.format("Navigation list. %s, %d of %d", it[1], nav_index, #nav_items)
end

local function say_nav()
    local it = nav_items[nav_index]
    speech.say(string.format("%s, %d of %d", it[1], nav_index, #nav_items), true)
end

function M.nav_toggle()
    if nav_items then
        nav_items = nil
        speech.say("Closed", true)
        return
    end
    if not nav_place() then
        speech.say("Navigation is available in the ship view and the System Map", true)
        return
    end
    local items = {}
    for _, it in ipairs(NAV) do
        local b = find(it[2])
        if b and b:GetIsEnabled() then items[#items + 1] = it end
    end
    if #items == 0 then
        speech.say("Navigation is not available here", true)
        return
    end
    nav_items, nav_index = items, 1
    say_nav()
end

function M.nav_step(dir)
    local i = nav_index + dir
    if nav_items[i] then nav_index = i end
    say_nav()
end

function M.nav_edge(last)
    nav_index = last and #nav_items or 1
    say_nav()
end

function M.nav_close()
    if not nav_items then return false end
    nav_items = nil
    speech.say("Closed", true)
    return true
end

function M.nav_enter()
    local it = nav_items[nav_index]
    nav_items = nil
    local b = find(it[2])
    if not b then
        speech.say(it[1] .. " is not available here", true)
        return
    end
    print("[VoyagerAccess] nav: " .. it[1] .. "\n")
    -- Wait One Cycle is a hold button (bRequiresHold): a tap did nothing
    -- (2026-10-14). Hold it as the away mission Confirm is held.
    local ok, hold = pcall(function() return b.bRequiresHold end)
    if ok and hold then
        speech.say(it[1] .. ", holding", true)
        b:HandleButtonPressed()
        local name = it[2]
        ExecuteInGameThreadWithDelay(2500, function()
            pcall(function()
                local nb = find(name)
                if nb then nb:HandleButtonReleased() end
                print("[VoyagerAccess] nav: released " .. name .. "\n")
            end)
        end)
        return
    end
    b:HandleButtonPressed()
    b:HandleButtonReleased()
    b:HandleButtonClicked()
    -- Ship view and System map are announced by help.lua once they are up.
    if it[2] ~= "ShowShipButton" and it[2] ~= "ShowSystemButton" then speech.say(it[1], true) end
end

-- Left and Right switch the Overview's tabs, as in a room window; the new
-- tab is read by popups.lua when its text changes. True when it did.
function M.overview_tab(dir)
    local w = nil
    for _, x in ipairs(FindAllOf("WBP_OverviewInfoWidget_C") or {}) do
        if x:IsValid() and x:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(x) then w = x end
    end
    if not w then return false end
    local wp = w:GetFullName():match("^%S+%s+(.+)$") .. "."
    local want = dir < 0 and "PreviousTabButton" or "NextTabButton"
    for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
        local p = b:IsValid() and b:GetFullName():match("^%S+%s+(.+)$")
        if p and p:sub(1, #wp) == wp and p:find("%." .. want .. "$") then
            b:HandleButtonPressed()
            b:HandleButtonReleased()
            b:HandleButtonClicked()
            return true
        end
    end
    return true
end

-- A call coming in shows the Incoming Calls button on the navigation bar
-- and nothing else: the mod said nothing, the objective only said "Answer
-- the incoming distress call", and a forum player could not find how to
-- answer the array's hail in the first mission (2026-10-15). Said once when
-- the button appears, while the bar is up (ship view or System Map).
local call_waiting = false
local function poll_calls()
    if not find("ShowShipButton") and not find("ShowSystemButton") then return end   -- bar not up
    local b = find("IncomingCallsButton")
    local waiting = b ~= nil
    if waiting then
        local ok, en = pcall(function() return b:GetIsEnabled() end)
        waiting = not (ok and en == false)
    end
    if waiting and not call_waiting then
        print("[VoyagerAccess] view: incoming call waiting\n")
        speech.say("Incoming call. To answer, press N and choose Incoming calls.", false)
    end
    call_waiting = waiting
end

function M.install()
    require("keys").on("v", M.toggle)
    require("keys").on("n", M.nav_toggle)
    LoopInGameThreadWithDelay(1000, function()
        local ok, err = pcall(poll_calls)
        if not ok then print("[VoyagerAccess] view calls error: " .. tostring(err) .. "\n") end
    end)
end

return M
