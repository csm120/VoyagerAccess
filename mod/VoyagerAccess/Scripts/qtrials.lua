-- Q Trials setup (WBP_Sandbox_Setup_C, full game), found 2026-10-14 in the
-- VM. After its warning page (popups.lua and the window button list), the
-- setup page has: the ship tabs (U.S.S. Voyager, U.S.S. Equinox), a captain
-- picker, the starting hero slots (pickers in HeroPlaqueLayout), a Q
-- Modifier picker, a Q Challenges picker and Start Game. Every picker opens
-- a selection window drawn on its own layer: captains, heroes (several can
-- be chosen, "01/08"), Q modifiers, challenge levels.
--
-- The plus buttons had no labels and the game's arrows moved by screen
-- position (through five leftover hero templates that are never drawn), so
-- each page and window is one list here, Up and Down in reading order,
-- "n of m" on each item (Casey: new screens are lists).
--
-- The selection windows' buttons are created with the game instance as
-- their outer, so their paths do not name the window, and the general
-- on-screen check says they are hidden; the open window is found from the
-- focused button's parents instead.
local speech = require("speech")
local screen = require("screen")

local M = {}

local NAV_LEFT, NAV_RIGHT, NAV_UP, NAV_DOWN = 0, 1, 2, 3   -- EUINavigation
local STOP = 3

local SETUP = "WBP_Sandbox_Setup_C_%d+%."
local CHOICES = {
    WBP_Sandbox_Setup_CaptainSelectionButton_C = "captain",
    WBP_Sandbox_Setup_HeroSelectionButton_C = "hero",
    WBP_Sandbox_Setup_QAmusementsPlaque_small_C = "modifier",
    WBP_Sandbox_Setup_QChallengesPlaque_small_C = "challenge",
}

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

local function valid(o) return o ~= nil and o:IsValid() end

local function text(w)
    if not valid(w) then return "" end
    local ok, s = pcall(function() return w:GetText():ToString() end)
    if not ok or type(s) ~= "string" or s:sub(1, 1) == "#" then return "" end
    s = require("text").prep(s)  -- icons beside numbers (text.lua)
    s = s:gsub("<[^>]*/>", ""):gsub("<[^>]*>", "")
    return (s:gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

local function sentence(s)
    s = s:gsub("%s+$", "")
    if s == "" or s:find("[%.!?]$") then return s end
    return s .. "."
end

local function join(parts)
    local out = {}
    for _, p in ipairs(parts) do
        if p and p ~= "" and p ~= "-" then out[#out + 1] = sentence(p) end
    end
    return table.concat(out, " ")
end

local function class_of(o)
    return o:GetClass():GetFName():ToString()
end

local function choice_kind(path)
    local cls = path and path:match("%.(WBP_Sandbox_Setup_[%w_]-_C)_%d+$")
    return cls and CHOICES[cls]
end

-- The hero window's Confirm is not named by its class.
function M.is_confirm(path)
    return path ~= nil and path:find("WBP_Sandbox_Setup_HeroSelection_C_%d+%.WidgetTree_%d+%.ConfirmButton$") ~= nil
end

-- The setup page's own items only: the warning's ABORT and ACCEPT are in
-- the same window and were read "Button" when this took them (2026-10-14).
local SETUP_ITEMS = { "CaptainModule.", "HeroesModule.", "QsAmusementsModule.", "QsTrialsModule." }
function M.handles(path)
    if path == nil then return false end
    if choice_kind(path) then return true end
    if not path:find(SETUP) then return false end
    if M.is_confirm(path) or path:find(SETUP .. "WidgetTree_%d+%.ConfirmButton$") then return true end
    for _, s in ipairs(SETUP_ITEMS) do
        if path:find(s, 1, true) then return true end
    end
    return false
end

-- { "Chakotay, Survivalist", "Command 40, Diplomacy 25, Security 30",
-- "Ability: Maquis Maneuver" } from a hero plaque; nil when it shows no hero.
local function plaque_parts(plaque, with_bonus)
    if not valid(plaque) then return nil end
    local name = text(plaque.HeroNameText)
    if name == "" then return nil end
    local sheet = plaque.HeroStatSheet
    local head = name
    local trait = valid(sheet) and valid(sheet.HeroTraits) and text(sheet.HeroTraits.TraitText) or ""
    if trait ~= "" and trait ~= "Text Block" then head = head .. ", " .. trait end
    local parts = { head }
    if with_bonus then
        local bonus = text(plaque.HeroBonus_TXT)
        if bonus ~= "" and bonus ~= "-" then parts[#parts + 1] = "Bonus: " .. bonus end
    end
    local okS, skills = pcall(function() return require("rooms").skills_of(sheet) end)
    if okS and skills and skills ~= "" then parts[#parts + 1] = skills end
    local ability = text(plaque.AbilityName)
    if ability ~= "" and ability ~= "-" and ability ~= "Text Block" then parts[#parts + 1] = "Ability: " .. ability end
    return parts
end

-- The setup window a path is in.
local function setup_of(path)
    local p = path and path:match("^(.-WBP_Sandbox_Setup_C_%d+)%.")
    local w = p and StaticFindObject(p)
    return valid(w) and w or nil, p
end

-- The shown widgets of the given classes (name -> true) inside the window
-- at wpath, from its own widget tree in layout order (screen.walk), not by
-- searching every widget of the class in the game (review of 0.3.70,
-- 2026-10-22). Only those whose path is under the window, as before.
local function in_window(wpath, classes)
    local w = StaticFindObject(wpath)
    local found = {}
    if not (valid(w) and screen.shown(w)) then return found end
    local prefix = wpath .. "."
    screen.walk(w, function(x)
        if not classes[x:GetClass():GetFName():ToString()] then return false end
        local p = path_of(x)
        if p and p:sub(1, #prefix) == prefix then found[#found + 1] = x end
        return true
    -- List and entry box entries too: the old search found buttons wherever
    -- they sat.
    end)
    return found
end

-- The setup page's items, as paths, in reading order.
local function setup_items(wpath)
    local plus = in_window(wpath, { WBP_PlusButton_C = true })
    local function under(_, needle)
        local found = {}
        for _, b in ipairs(plus) do
            if path_of(b):find(needle, 1, true) then found[#found + 1] = b end
        end
        return found
    end
    -- The ship tabs never take keyboard focus: the ship is read with the
    -- page title, and Left and Right change it (M.switch_ship).
    local out = {}
    for _, b in ipairs(under("WBP_PlusButton_C", "CaptainModule.")) do out[#out + 1] = path_of(b) end
    -- The hero slots are the pickers in HeroPlaqueLayout, in grid order.
    local slots = {}
    for _, b in ipairs(under("WBP_PlusButton_C", ".HeroPlaqueLayout.")) do
        local p = path_of(b)
        if p:find("HeroesModule.", 1, true) then
            local idx = 0
            pcall(function()
                local picker = b:GetOuter():GetOuter()
                idx = picker:GetParent():GetChildIndex(picker)
            end)
            slots[#slots + 1] = { idx = idx, path = p }
        end
    end
    table.sort(slots, function(a, b) return a.idx < b.idx end)
    for _, s in ipairs(slots) do out[#out + 1] = s.path end
    for _, needle in ipairs({ "QsAmusementsModule.", "QsTrialsModule." }) do
        for _, b in ipairs(under("WBP_PlusButton_C", needle)) do out[#out + 1] = path_of(b) end
    end
    local w = StaticFindObject(wpath)
    local start = valid(w) and w.ConfirmButton
    if valid(start) and screen.shown(start) then out[#out + 1] = path_of(start) end
    return out
end

-- The open selection window holding a choice button: up its parents to the
-- window's root, whose outer's outer is the window.
local function window_of_choice(b)
    local cur, d = b, 0
    while d < 32 do
        local par = cur:GetParent()
        if not valid(par) then break end
        cur, d = par, d + 1
    end
    local tree = cur:GetOuter()
    local win = valid(tree) and tree:GetOuter()
    return valid(win) and win or nil
end

-- A selection window's buttons, in the order they are laid out.
local function choice_items(b)
    local parent = b:GetParent()
    if not valid(parent) then return { path_of(b) } end
    local out = {}
    for i = 0, parent:GetChildrenCount() - 1 do
        local c = parent:GetChildAt(i)
        if valid(c) and CHOICES[class_of(c)] and c:IsVisible() then out[#out + 1] = path_of(c) end
    end
    local win = window_of_choice(b)
    local confirm = valid(win) and win.ConfirmButton
    if valid(confirm) and confirm:IsVisible() and choice_kind(path_of(b)) == "hero" then out[#out + 1] = path_of(confirm) end
    return out
end

local state = nil
local list = {}
local pending = nil   -- { path, title }: a page or window title, said with its first item

local function wire()
    for i, p in ipairs(list) do
        local b = StaticFindObject(p)
        if valid(b) then pcall(function()
            local up, down = list[i - 1] and StaticFindObject(list[i - 1]), list[i + 1] and StaticFindObject(list[i + 1])
            if valid(up) then b:SetNavigationRuleExplicit(NAV_UP, up) else b:SetNavigationRuleBase(NAV_UP, STOP) end
            if valid(down) then b:SetNavigationRuleExplicit(NAV_DOWN, down) else b:SetNavigationRuleBase(NAV_DOWN, STOP) end
            b:SetNavigationRuleBase(NAV_LEFT, STOP)
            b:SetNavigationRuleBase(NAV_RIGHT, STOP)
        end) end
    end
    print(string.format("[VoyagerAccess] qtrials: %d items wired\n", #list))
end

local function position(path)
    for i, p in ipairs(list) do
        if p == path then return string.format("%d of %d", i, #list) end
    end
    return nil
end

-- The chosen captain's name, to mark them in the hero list: the captain
-- slot's own plaque.
local function captain_name()
    for _, b in ipairs(FindAllOf("WBP_PlusButton_C") or {}) do
        local p = b:IsValid() and path_of(b)
        if p and p:find("^/Engine/Transient%.") and p:find("CaptainModule.", 1, true) then
            local picker = b:GetOuter() and b:GetOuter():GetOuter()
            local n = valid(picker) and valid(picker.HeroPlaque) and text(picker.HeroPlaque.HeroNameText) or ""
            if n ~= "" then return n end
        end
    end
    return nil
end

local function counter_of(win)
    local c = valid(win) and text(win.CrewCounter_TXT) or ""
    local a, b = c:match("^(%d+)%s*/%s*(%d+)$")
    if a then return tonumber(a), tonumber(b) end
    return nil
end

-- The ship tabs of the setup window at wpath, Voyager first.
local function ship_tabs(wpath)
    local found = in_window(wpath, { WBP_Sandbox_Setup_TabButton_C = true })
    local tabs = {}
    for _, name in ipairs({ "VoyagerButton", "EquinoxButton" }) do
        for _, b in ipairs(found) do
            if path_of(b):find("%." .. name .. "$") then tabs[#tabs + 1] = b end
        end
    end
    return tabs
end

local function tab_locked(b)
    -- The lock box itself (Locker_HB), not the word: "Locked" is
    -- translated (outside review, 2026-10-17). The fallback that still
    -- looked for the English word went (review of 0.3.70, 2026-10-22): it
    -- matched in English only; without the box the log says so.
    local okh, shown = pcall(function() return b.Locker_HB and b.Locker_HB:IsValid() and screen.shown(b.Locker_HB) end)
    if okh and shown ~= nil then return shown == true end
    print("[VoyagerAccess] qtrials: ship tab without its lock box\n")
    return false
end

-- "Ship: U.S.S. Voyager. An Intrepid-class starship offering a balanced
-- experience. Difficulty Normal, Decks 15, ..." for the selected tab.
local function ship_text(wpath)
    local name = nil
    local others = {}
    for _, b in ipairs(ship_tabs(wpath)) do
        local n = text(b.ButtonName_TXT)
        local okS, sel = pcall(function() return b:GetSelected() end)
        if okS and sel then name = n
        else others[#others + 1] = n .. (tab_locked(b) and ", locked" or "") end
    end
    local parts = { "Ship: " .. (name or "unknown") }
    for _, x in ipairs(in_window(wpath, { WBP_Sandbox_Setup_ShipInfo_C = true })) do
        do
            parts[#parts + 1] = text(x.Description_Text)
            local facts = {}
            for _, pair in ipairs({ { "Difficulty", "Difficulty_TXT" }, { "Decks", "Decks_TXT" },
                { "Building space", "BuildingSpace_TXT" }, { "Starting max. hull", "MaxHull_TXT" },
                { "Starting hero slots", "HeroSlots_TXT" }, { "Starting crew", "StartCrew_TXT" } }) do
                local v = text(x[pair[2]])
                if v ~= "" then facts[#facts + 1] = pair[1] .. " " .. v end
            end
            if #facts > 0 then parts[#parts + 1] = table.concat(facts, ", ") end
        end
    end
    if #others > 0 then parts[#parts + 1] = "Left and Right change ship. Also: " .. table.concat(others, "; ") end
    return join(parts)
end

-- A setup page item's words, without position.
local function setup_label(b, path)
    local picker = b:GetOuter() and b:GetOuter():GetOuter()
    if path:find("CaptainModule.", 1, true) then
        local who = valid(picker) and plaque_parts(picker.HeroPlaque, true) or { "none chosen" }
        who[1] = "Captain: " .. who[1]
        return who
    end
    if path:find("HeroesModule.", 1, true) then
        -- Slots are numbered among the slots, not the whole list.
        local n, slot = 0, nil
        for _, p in ipairs(list) do
            if p:find("HeroesModule.", 1, true) then
                n = n + 1
                if p == path then slot = n end
            end
        end
        -- A slot's hidden plaque keeps the last hero's name: slot 1 was read
        -- "Kes" while the screen showed it empty, after every pick in the
        -- picker had been undone (VM, 2026-10-18).
        local okv, shown = pcall(function() return require("screen").shown(picker.HeroPlaque) end)
        local who = valid(picker) and not (okv and shown == false) and plaque_parts(picker.HeroPlaque, false) or { "empty" }
        who[1] = "Hero slot " .. (slot or "") .. ": " .. who[1]
        return who
    end
    if path:find("QsAmusementsModule.", 1, true) then
        local name = valid(picker) and text(picker.QAmusementName_TXT) or ""
        local desc = valid(picker) and text(picker.QAmusementDescr_TXT) or ""
        if name == "" or name:find("^Select") then name = "none chosen" end
        return { "Q Modifier: " .. name, desc }
    end
    if path:find("QsTrialsModule.", 1, true) then
        local name = valid(picker) and text(picker.QChallengeName_TXT) or ""
        local desc = valid(picker) and text(picker.QChallengeDescr_TXT) or ""
        return { "Q Challenges: " .. name, desc }
    end
    if path:find("%.ConfirmButton$") then
        -- Disabled until the setup is complete (1 hero of 8 in the VM,
        -- 2026-10-14); it was read as if it would start.
        local okE, en = pcall(function() return b:GetIsEnabled() end)
        if okE and en == false then return { "Start Game, not available yet" } end
        return { "Start Game" }
    end
    return { "Button" }
end

local function choice_label(b, path, kind)
    local parts = {}
    if kind == "captain" or kind == "hero" then
        parts = plaque_parts(b.HeroPlaque, kind == "captain") or { "Unknown" }
        local okM, marked = pcall(function() return b.bIsMarked end)
        if okM and marked then parts[1] = parts[1] .. ", chosen" end
        if kind == "hero" then
            local cap = captain_name()
            if cap and parts[1]:sub(1, #cap) == cap then parts[1] = parts[1] .. ", your captain, cannot be chosen" end
        end
    else
        local name = text(b.Level_TXT)
        local desc = text(b.ModifierDescr_TXT)
        if desc == "" then desc = text(b.ChallengeDescr_TXT) end
        local flags = ""
        local okL, locked = pcall(function() return b.IsLocked end)
        if okL and locked then flags = flags .. ", locked" end
        local okS, sel = pcall(function() return b.IsSelected or b.bIsMarked end)
        if okS and sel then flags = flags .. ", selected" end
        parts[#parts + 1] = name .. flags
        parts[#parts + 1] = desc
    end
    return parts
end

local TITLES = { captain = "Choose a captain", hero = "Choose heroes", modifier = "Choose a Q Modifier",
    challenge = "Choose a Q Challenges level" }

function M.label(b, path)
    -- The hero window's Confirm sits under the setup window's path too.
    if M.is_confirm(path) then return M.confirm_label(b, path) end
    local kind = choice_kind(path)
    local key, items, title
    if kind then
        local win = window_of_choice(b)
        key = (valid(win) and path_of(win) or "?") .. ":" .. kind
        if key ~= state or not position(path) then
            items = choice_items(b)
            title = TITLES[kind]
            if kind == "hero" then
                local _, max = counter_of(win)
                if max then title = title .. ", up to " .. max end
            end
        end
    else
        local _, wpath = setup_of(path)
        if not wpath then return nil end
        key = wpath .. ":setup"
        -- Built again when the item is missing: a list made while the
        -- warning showed was empty, and the page had no positions.
        if key ~= state or not position(path) then
            items = setup_items(wpath)
            -- Not when coming back from one of its pickers: that repeated
            -- the ship's whole description (2026-10-14).
            local from_picker = state and state:sub(1, #wpath) == wpath and not state:find(":setup$")
            if not from_picker and #items > 0 and key ~= state then
                title = "Q Trials setup. " .. ship_text(wpath)
            end
        end
    end
    if items then
        state = key
        list = items
        wire()
        pending = title and { path = path, title = title } or nil
    end
    local said_title = nil
    if pending and pending.at and os.clock() - pending.at > 1 then pending = nil end
    if pending and pending.path == path then
        said_title = pending.title
        pending.at = pending.at or os.clock()
    elseif pending and pending.at then
        pending = nil
    end
    local parts = kind and choice_label(b, path, kind) or setup_label(b, path)
    local pos = position(path)
    if pos then parts[1] = parts[1] .. ", " .. pos end
    if said_title then table.insert(parts, 1, said_title) end
    return join(parts)
end

-- The hero window's Confirm, labelled with how many are chosen.
function M.confirm_label(b, path)
    local win = window_of_choice(b)
    local n, max = counter_of(win)
    local label = "Confirm"
    if n then label = label .. ", " .. n .. " of " .. max .. " chosen" end
    local pos = position(path)
    return sentence(label .. (pos and (", " .. pos) or ""))
end

-- Enter on a hero: choose or remove them, and say which and the count.
-- True when it handled the key.
function M.enter(b, path)
    local kind = choice_kind(path)
    -- A captain, Q Modifier or Q Challenges level: the list closes on the
    -- click, and Casey heard nothing about the choice until he arrowed back
    -- to it (2026-10-14). Say what was chosen, as heroes do.
    if kind == "captain" or kind == "modifier" or kind == "challenge" then
        local name = kind == "captain" and (valid(b.HeroPlaque) and text(b.HeroPlaque.HeroNameText) or "")
            or text(b.Level_TXT)
        -- Captain buttons have no IsLocked bool (it came back as an object
        -- and every captain read "locked", VM 2026-10-14): only a real true.
        local okL, locked = pcall(function() return b.IsLocked end)
        if okL and locked == true then
            speech.say(name .. " is locked", true)
            return true
        end
        b:HandleButtonPressed()
        b:HandleButtonReleased()
        b:HandleButtonClicked()
        local s = kind == "captain" and (name .. " is your captain")
            or ((kind == "modifier" and "Q Modifier: " or "Q Challenges: ") .. name .. ", chosen")
        -- Said now, and the slot the game focuses as the list closes (on the
        -- next tick, probe 2026-10-22) is said after it: say_long holds the
        -- focus line behind it. It replaces a wait of 300 ms that read no
        -- state and put the sentence over the slot (the open point of the
        -- review of 0.3.70, 2026-10-22).
        print("[VoyagerAccess] qtrials: " .. s .. "\n")
        speech.say_long(s, true)
        return true
    end
    if kind ~= "hero" then return false end
    local win = window_of_choice(b)
    local name = valid(b.HeroPlaque) and text(b.HeroPlaque.HeroNameText) or require("tr").word("Hero")
    local okW, was_marked = pcall(function() return b.bIsMarked end)
    was_marked = okW and was_marked == true
    b:HandleButtonPressed()
    b:HandleButtonReleased()
    b:HandleButtonClicked()
    local wp = valid(win) and path_of(win)
    -- Read now: the hero's bIsMarked and the counter are the new ones in the
    -- same call as the click (probe 2026-10-22: 00/08 to 01/08 and back),
    -- not 300 ms later. Focus stays on the hero, so nothing talks over it.
    pcall(function()
        local nb = StaticFindObject(path)
        local w = wp and StaticFindObject(wp)
        local marked = valid(nb) and nb.bIsMarked
        local n, max = counter_of(w)
        local s = name .. (marked and " chosen" or " not chosen")
        if n then s = s .. ", " .. n .. " of " .. max end
        -- A full team ignores a new hero; "Maxwell Burke not chosen, 8
        -- of 8" read like Enter not working (Casey, 2026-10-14).
        if not marked and n and n >= max and not was_marked then
            s = name .. " not chosen: the team is full, " .. n .. " of " .. max .. ". Enter on a chosen hero removes them"
        end
        print("[VoyagerAccess] qtrials: " .. s .. "\n")
        speech.say(s, true)
    end)
    return true
end

-- Up or Down onto a disabled item (Start Game before the setup is complete):
-- the game never moves focus to a disabled button, so Down from Q
-- Challenges did nothing (2026-10-14). The mod moves it. True when handled.
function M.step(path, dir)
    if not (path and M.handles(path)) then return false end
    for i, p in ipairs(list) do
        if p == path then
            local t = list[i + dir] and StaticFindObject(list[i + dir])
            -- Valid first: a null object's method can crash past pcall.
            local okE, en = pcall(function() return valid(t) and t:GetIsEnabled() end)
            if valid(t) and okE and en == false then
                t:SetFocus()
                return true
            end
            return false
        end
    end
    return false
end

-- Backspace in a selection list (captain, heroes, Q Modifier, Q Challenges):
-- close it with its picker's CloseSelectionButton and focus the picker
-- again. The picker counts as hidden while its list is open, so Backspace
-- went on back to the main menu's NEW Q TRIAL behind the setup and the
-- setup was lost (Casey, 2026-10-14). True when it handled the key.
function M.back(path)
    if not path then return false end
    local b = StaticFindObject(path)
    if not valid(b) then return false end
    local win = nil
    if M.is_confirm(path) then
        win = StaticFindObject(path:match("^(.-WBP_Sandbox_Setup_HeroSelection_C_%d+)%."))
    elseif choice_kind(path) then
        win = window_of_choice(b)
    end
    if not valid(win) then return false end
    -- The list's own CloseSelectionButton (its WidgetTree); the picker that
    -- opened it is the list's outer's outer (VM, 2026-10-14).
    local okC, close = pcall(function() return win.CloseSelectionButton end)
    if not (okC and valid(close)) then return false end
    local tree = win:GetOuter()
    local picker = valid(tree) and tree:GetOuter() or nil
    print("[VoyagerAccess] qtrials: closing the selection list\n")
    close:HandleButtonPressed()
    close:HandleButtonReleased()
    close:HandleButtonClicked()
    if not valid(picker) then return true end
    local pp = path_of(picker)
    -- On the next tick, not 300 ms later: the list is closed in the same
    -- call, and the game puts focus back into the setup on the next tick
    -- by itself (probe 2026-10-22); the slot's button is focused after that.
    ExecuteInGameThread(function()
        pcall(function()
            local np = StaticFindObject(pp)
            if valid(np) and valid(np.OpenSelectionButton) then np.OpenSelectionButton:SetFocus() end
        end)
    end)
    return true
end

-- Left and Right on the setup page: the other ship. True when it handled
-- the key.
function M.switch_ship(path, dir)
    if not (path and path:find(SETUP) and not choice_kind(path) and not M.is_confirm(path)) then return false end
    local _, wpath = setup_of(path)
    if not wpath then return false end
    local tabs = ship_tabs(wpath)
    if #tabs < 2 then return true end
    local cur = 1
    for i, b in ipairs(tabs) do
        local okS, sel = pcall(function() return b:GetSelected() end)
        if okS and sel then cur = i end
    end
    local nxt = tabs[cur + dir]
    if not nxt then
        speech.say(text(tabs[cur].ButtonName_TXT) .. " is " .. (dir < 0 and "the first" or "the last") .. " ship", true)
        return true
    end
    if tab_locked(nxt) then
        speech.say(text(nxt.ButtonName_TXT) .. " is locked", true)
        return true
    end
    nxt:HandleButtonPressed()
    nxt:HandleButtonReleased()
    nxt:HandleButtonClicked()
    -- Read now: the new tab is selected and the ship info shows the new
    -- ship in the same call as the click (probe 2026-10-22), not 300 ms
    -- later.
    pcall(function()
        local s = ship_text(wpath)
        print("[VoyagerAccess] qtrials: " .. s .. "\n")
        speech.say(s, true)
    end)
    return true
end

-- Focus went somewhere else (the warning, the main menu): the next visit
-- starts with the page title again.
function M.away()
    state, pending = nil, nil
end

-- Home and End: the ends of the list.
function M.edge(path, last)
    if not M.handles(path) or #list == 0 then return false end
    local b = StaticFindObject(last and list[#list] or list[1])
    if valid(b) then b:SetFocus() end
    return true
end

-- The Overview's Q Trials tab lists the challenge levels
-- (WBP_Sandbox_Setup_QChallengesPlaque_Overview: Level_TXT,
-- ChallengeDescr_TXT, IsLocked). Read by the generic label it came out as
-- "Spatial phenomena spawn 50% more often, 3 of 11. Crew treatment time
-- increases by 60%., Level 02" (VM, 2026-10-17). Only the trial's own level
-- is unlocked there, so locked is said as "not active".
function M.overview_plaque_label(b)
    local level = (text(b.Level_TXT):gsub("(%d+)", function(n) return tostring(tonumber(n)) end))
    local descr = (text(b.ChallengeDescr_TXT):gsub("%.?%s*$", "."))
    if level == "" and descr == "." then return nil end
    -- Left and Right switch the Overview's tabs (view.lua); the game also
    -- took Right from a row into the Q Modifier picker, and the tabs went
    -- silent after it (VM, 2026-10-17). EUINavigation Left 0, Right 1; Stop 3.
    pcall(function() b:SetNavigationRuleBase(0, 3); b:SetNavigationRuleBase(1, 3) end)
    -- Level and state first: the count goes after the first sentence.
    -- "Level" by name: it is off the line-wide pass (tr.lua, 2026-10-24).
    return string.format("%s, %s: %s", level ~= "" and level or require("tr").word("Level"), b.IsLocked and "not active" or "active", descr)
end

return M
