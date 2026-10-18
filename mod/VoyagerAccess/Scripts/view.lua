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
    -- Said at once: the full line waits for the view to settle, about 1.6 s
    -- after the key (VM log, 2026-10-17), and a player found the keys
    -- sluggish (forum, TheRev, 2026-10-17). help.lua then says only what is
    -- selected.
    M.toggled_at = os.clock()
    speech.say(to_map and "System map" or "Ship view", true)
end

-- N: the navigation bar as a list (Casey, 2026-10-11: "how do I get to the
-- other tabs from ship view?"). The bar (WBP_NavigationBar) takes only the
-- mouse and is shown only in the ship and map views. Up and Down choose,
-- Enter presses, Backspace closes the list. N is unbound in the game.
local NAV = {
    { "Ship view", "ShowShipButton" }, { "System map", "ShowSystemButton" },
    { "Sector map", "ShowSectorButton" }, { "Overview", "OverviewButton" },
    { "Research", "ResearchButton" }, { "Wait one cycle", "WaitOneCycleButton" },
    { "Incoming calls", "IncomingCallsButton" }, { "Sector switch, leave for the next sector", "SectorSwitchButton" },
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

-- Sector switch leaves the sector at once: active missions were cancelled
-- with no warning heard (State of Flux, VM, 2026-10-15). The game's own
-- warning is on its hover; the first Enter says it and a second Enter
-- within a few seconds leaves.
local switch_armed_until = -100

function M.nav_enter()
    local it = nav_items[nav_index]
    if it[2] == "SectorSwitchButton" and os.clock() > switch_armed_until then
        switch_armed_until = os.clock() + 8
        speech.say("Leaving the sector cancels all active missions, and heroes marked unavailable are lost. "
            .. "Press Enter again to leave.", true)
        return
    end
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
-- The Overview's Heroes tab: a grid of hero cards (WBP_Hero_InfoCardButton,
-- plain UMG Buttons the mod's button lists do not take) and the selected
-- hero's details. Only the first hero's details could be heard (Q Trials,
-- VM, 2026-10-15). Up and Down walk the cards; each step selects the card as
-- a click does (its own OnButtonClicked event) and reads the details.
local hero_index = nil

local function heroes_panel()
    for _, w in ipairs(FindAllOf("WBP_Hero_Overview_C") or {}) do
        if w:IsValid() and w:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(w) then return w end
    end
    return nil
end

function M.heroes_open()
    local open = heroes_panel() ~= nil
    if not open then hero_index = nil end
    return open
end

local function texts_in(prefix)
    local out, seen = {}, {}
    for _, cls in ipairs({ "TextBlock", "RichTextBlock" }) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            local tp = t:IsValid() and t:GetFullName():match("^%S+%s+(.+)$")
            if tp and not seen[tp] and tp:sub(1, #prefix) == prefix and screen.shown(t) then
                seen[tp] = true
                local ok, s = pcall(function() return t:GetText():ToString() end)
                if ok then out[tp:match("([%w_]+)$")] = require("text").prep(s):gsub("<[^>]*>", "") end
            end
        end
    end
    return out
end

local function hero_cards()
    local panel = heroes_panel()
    if not panel then return {} end
    local pp = panel:GetFullName():match("^%S+%s+(.+)$") .. "."
    -- In the campaign the cards are created with the game instance as their
    -- outer, so their path is not under the panel ("0 heroes", VM,
    -- 2026-10-16); climb the parents, crossing widget trees, instead.
    local panel_path = pp:sub(1, -2)
    local cards = {}
    for _, c in ipairs(FindAllOf("WBP_Hero_InfoCardButton_C") or {}) do
        local cp = c:IsValid() and c:GetFullName():match("^%S+%s+(.+)$")
        if cp and screen.inside(c, panel_path) and screen.shown(c) then
            local parent, idx, pidx = nil, 0, 0
            pcall(function()
                parent = c:GetParent()
                idx = parent:GetChildIndex(c)
                pidx = parent:GetParent():GetChildIndex(parent)
            end)
            cards[#cards + 1] = { w = c, path = cp, key = pidx * 1000 + idx }
        end
    end
    table.sort(cards, function(a, b) return a.key < b.key end)
    return cards
end

local function card_text(c)
    local parts = {}
    for _, cls in ipairs({ "TextBlock" }) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            local tp = t:IsValid() and t:GetFullName():match("^%S+%s+(.+)$")
            if tp and tp:sub(1, #c.path + 1) == c.path .. "." and screen.shown(t) then
                local ok, s = pcall(function() return t:GetText():ToString() end)
                -- Skill values without their icons ("25, 29") are left out.
                if ok and s ~= "" and not s:match("^[%d%s%+%-]+$") then parts[#parts + 1] = s end
            end
        end
    end
    return table.concat(parts, ", ")
end

local function hero_details()
    local panel = heroes_panel()
    if not panel then return "" end
    local by = texts_in(panel:GetFullName():match("^%S+%s+(.+)$") .. ".")
    local out = {}
    local function add(k, label)
        local v = by[k]
        if v and v ~= "" then out[#out + 1] = (label and (label .. ": ") or "") .. v:gsub("%.%s*$", "") end
    end
    add("SelectedHeroTrait_1", "Trait")
    add("SelectedHeroTrait_2", "Trait")
    add("SelectedHeroCondition_1")
    add("SelectedHeroCondition_2")
    add("SelectedHeroLocation", "Location")
    -- "Passive Bonus" or "Combat Ability", as the header says.
    local head = by.CaptainBonusHeader_TXT
    if not head or head == "" then head = by.CombatAbilityHeader_TXT end
    add("AbilityTextBlock", (head and head ~= "") and head or "Bonus")
    add("SelectedHeroBiography")
    return table.concat(out, ". ") .. "."
end

function M.hero_count()
    return #hero_cards()
end

function M.hero_step(dir, edge)
    local cards = hero_cards()
    if #cards == 0 then return false end
    if edge then
        hero_index = dir < 0 and 1 or #cards
    else
        hero_index = math.max(1, math.min(#cards, (hero_index or 0) + dir))
    end
    local c = cards[hero_index]
    local name = card_text(c)
    -- The name first: the card's texts came out "Not recruited, Tuvok"
    -- (VM, 2026-10-17).
    name = (name:gsub("^([^,]*[Rr]ecruited), (.+)$", "%2, %1"))
    -- And "Rank 01, Neelix" (the same day).
    name = (name:gsub("^[Rr]ank 0*(%d+), (.+)$", "%2, rank %1"))
    pcall(function() c.w["BndEvt__WBP_Hero_InfoCardButton_Button_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature"](c.w) end)
    speech.say(string.format("%s, %d of %d", name ~= "" and name or "Hero", hero_index, #cards), true)
    ExecuteInGameThreadWithDelay(250, function()
        pcall(function() speech.say(hero_details(), false) end)
    end)
    return true
end

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
            -- After the new tab is in place: forgotten at once, the old tab
            -- was read again and the new one missed (VM, 2026-10-17).
            ExecuteInGameThreadWithDelay(400, function() pcall(require("popups").forget, "WBP_OverviewInfoWidget_C") end)
            -- The game gets the same arrow: on the Q Trials tab it moved
            -- focus into the Q Modifier picker instead (VM, 2026-10-15). The
            -- tab is read as a whole, so the game's focus is parked.
            -- Except on the Q Trials tab, whose challenge levels are a list:
            -- parked there, Down went to CLOSE (VM, 2026-10-17). Its active
            -- level (the one not locked) takes focus.
            ExecuteInGameThreadWithDelay(150, function()
                local first, active = nil, nil
                for _, x in ipairs(FindAllOf("WBP_Sandbox_Setup_QChallengesPlaque_Overview_C") or {}) do
                    if x:IsValid() and x:GetFullName():find(" /Engine/Transient.", 1, true) and screen.shown(x) then
                        first = first or x
                        if not x.IsLocked and not active then active = x end
                    end
                end
                local target = active or first
                if target then
                    pcall(function() target:SetFocus() end)
                else
                    pcall(require("focus").park_focus)
                end
            end)
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
