-- The Tech Tree (opened from the Science Laboratory's Research button) was
-- silent with nothing focused (2026-10-14). While it is open it is a list:
-- the five tiers, then the current category's technologies in tier order,
-- each with its state. Up and Down move, Home and End go to the ends, Left
-- and Right switch category (Engineering, Crew, Science, Combat, Borg),
-- Enter does what a click on the item does, Escape closes the tree (the
-- game's own).
--
-- Read live: WBP_TierWidget (TierButton; bAlreadyResearched,
-- bCanBeresearched, bCurrentResearch) and WBP_TechWidget in a TechGrid
-- (GridSlot Row is the tier minus one; RegularTechButton; TechName,
-- bAlreadyResearched, bCanBeresearchItem, bCurrentResearch, bObfuscate).
-- The tabs are WBP_CommonButton_RoomMgmt_V2 in WBP_TechTreeTabWidget
-- (ButtonName, Selected); PreviousTabButton and NextTabButton switch them.

local speech = require("speech")
local screen = require("screen")

local M = {}

local list = nil    -- { items = { {text, button path} }, index, tab }

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

local function live(o)
    return o and o:IsValid() and o:GetFullName():find(" /Engine/Transient.", 1, true) ~= nil
end

local function open_now()
    for _, b in ipairs(FindAllOf("WBP_TechTree_TierButton_C") or {}) do
        if live(b) and screen.shown(b) then return true end
    end
    return false
end

local function state(researched, can, current)
    if current then return "researching" end
    if researched then return "researched" end
    if can then return "available" end
    return "locked"
end

local function tab_name()
    for _, b in ipairs(FindAllOf("WBP_CommonButton_RoomMgmt_V2_C") or {}) do
        if live(b) and b:GetFullName():find("TechTreeTabWidget", 1, true) and screen.shown(b) then
            local ok, sel = pcall(function() return b:GetSelected() end)
            if ok and sel then
                local okn, s = pcall(function() return b.ButtonName:GetText():ToString() end)
                if okn and s ~= "" then return s end
            end
        end
    end
    return "Tech tree"
end

local function build()
    local items = {}
    local tiers = {}
    for _, w in ipairs(FindAllOf("WBP_TierWidget_C") or {}) do
        if live(w) and screen.shown(w) then
            local n = ""
            pcall(function()
                for _, cls in ipairs({ "TextBlock" }) do
                    for _, t in ipairs(FindAllOf(cls) or {}) do
                        local tp = t:IsValid() and path_of(t)
                        if tp and tp:sub(1, #path_of(w) + 1) == path_of(w) .. "." and tp:match("%.TextBlock$") then
                            n = t:GetText():ToString()
                        end
                    end
                end
            end)
            local num = tonumber(n) or (#tiers + 1)
            tiers[#tiers + 1] = {
                n = num, researched = w.bAlreadyResearched == true,
                text = string.format("Tier %d, %s", num, state(w.bAlreadyResearched, w.bCanBeresearched, w.bCurrentResearch)),
                button = path_of(w.TierButton),
            }
        end
    end
    table.sort(tiers, function(a, b) return a.n < b.n end)
    local tier_done = {}
    for _, t in ipairs(tiers) do
        items[#items + 1] = t
        tier_done[t.n] = t.researched
    end
    local techs = {}
    for _, w in ipairs(FindAllOf("WBP_TechWidget_C") or {}) do
        if live(w) and screen.shown(w.RegularTechButton) then
            local row, col = 0, 0
            pcall(function() row, col = w.Slot.Row, w.Slot.Column end)
            local name = ""
            pcall(function() name = w.TechName:ToString() end)
            if w.bObfuscate or name == "" then name = "Unknown technology" end
            -- Row 0 is the starting technologies, above the Tier 1 band;
            -- row N is tier N. "row + 1" called Hyperspanner tier 3 while it
            -- sits in the Tier 2 band (VM screenshot, 2026-10-15).
            local st = state(w.bAlreadyResearched, w.bCanBeresearchItem, w.bCurrentResearch)
            local where = row == 0 and "starting technology" or ("tier " .. row)
            -- A tech in a tier not yet researched is locked by that tier.
            if st == "locked" and row > 0 and tier_done[row] == false then st = "locked until its tier is researched" end
            techs[#techs + 1] = {
                row = row, col = col,
                text = string.format("%s, %s, %s", name, where, st),
                button = path_of(w.RegularTechButton),
            }
        end
    end
    table.sort(techs, function(a, b)
        if a.row ~= b.row then return a.row < b.row end
        return a.col < b.col
    end)
    -- A tier has no description of its own in the game (its window shows
    -- only the cost), so it says which technologies it opens: "Tier 2" alone
    -- told a player nothing (forum, SightlessPsycho, 2026-10-17).
    local opens = {}
    for _, t in ipairs(techs) do
        if t.row > 0 then
            opens[t.row] = opens[t.row] or {}
            table.insert(opens[t.row], (t.text:match("^(.-), tier %d+")))
        end
    end
    for _, t in ipairs(tiers) do
        local names = opens[t.n]
        if names and #names > 0 then
            local known, unknown = {}, 0
            for _, n in ipairs(names) do
                if n == "Unknown technology" then unknown = unknown + 1 else known[#known + 1] = n end
            end
            if unknown > 0 then known[#known + 1] = unknown .. (unknown == 1 and " unknown technology" or " unknown technologies") end
            t.text = string.format("%s, opens %d: %s", t.text, #names, table.concat(known, ", "))
        end
    end
    for _, t in ipairs(techs) do items[#items + 1] = t end
    return items
end

local function say(interrupt)
    local it = list.items[list.index]
    if it then speech.say(string.format("%s, %d of %d", it.text, list.index, #list.items), interrupt) end
end

function M.open()
    return list ~= nil
end

-- For I (where am I): "Tech tree, Engineering. Small Battery Compartment,
-- tier 2, researching, 15 of 57" (it said only "Game.", VM, 2026-10-14).
function M.where()
    if not list then return nil end
    local it = list.items[list.index]
    local head = "Tech tree" .. ((list.tab and list.tab ~= "") and (", " .. list.tab) or "")
    if not it then return head end
    return string.format("%s. %s, %d of %d", head, it.text, list.index, #list.items)
end

local function refresh(keep_index)
    local items = build()
    if #items == 0 then return false end
    local index = 1
    if keep_index and list then index = math.min(list.index, #items) end
    list = { items = items, index = index, tab = tab_name() }
    return true
end

function M.step(dir)
    require("crumb").at("techtree: step")
    if list.items[list.index + dir] then list.index = list.index + dir end
    say(true)
end

function M.edge(last)
    list.index = last and #list.items or 1
    say(true)
end

-- Enter on an item opens WBP_TechTree_SelectedTechWidget ("Research.
-- Engineering Tier 2. 16. 60. 5. This will pause current analysis: ...")
-- with a StartResearchButton; it was silent (2026-10-14).
-- A researched or locked technology opens the same widget with a
-- description and no StartResearchButton ("Warp Drive. Superluminal travel
-- into the final frontier. Already researched").
-- A research in progress shows AbortResearchButton in the same widget; it
-- was neither read nor reachable, so a research could not be changed
-- (firefly82's review, 2026-10-19; the button found in the VM).
local function selected_view()
    for _, v in ipairs(FindAllOf("WBP_TechTree_SelectedTechWidget_C") or {}) do
        if live(v) and screen.shown(v) then
            local start, abort, prefix = nil, nil, path_of(v) .. "."
            for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
                if live(b) and screen.shown(b) and path_of(b):sub(1, #prefix) == prefix then
                    local n = b:GetFName():ToString()
                    if n == "StartResearchButton" then start = b
                    elseif n == "AbortResearchButton" then abort = b end
                end
            end
            return v, start, abort
        end
    end
    return nil
end

-- Its numbers have no words, only an icon before each (Cycle,
-- SciencePoints, Dilithium): the walk keeps the last icon's name. The
-- brush is checked valid before it is read (an unchecked read crashed the
-- game, 2026-10-11).
local ICONS = { Cycle = "cycles", SciencePoints = "research points" }

local function view_texts(view)
    local W = StaticFindObject("/Script/UMG.UserWidget")
    local PANEL = StaticFindObject("/Script/UMG.PanelWidget")
    local BTN = StaticFindObject("/Script/CommonUI.CommonButtonBase")
    local IMG = StaticFindObject("/Script/UMG.Image")
    local out, icon = {}, nil
    local function walk(w, depth)
        if depth > 40 or not (w and w:IsValid()) or not screen.shown(w) then return end
        if w:IsA(BTN) then return end
        if w:IsA(IMG) then
            pcall(function()
                local ro = w.Brush.ResourceObject
                if ro and ro:IsValid() then
                    local raw = ro:GetFName():ToString()
                    for key, word in pairs(ICONS) do
                        if raw:find(key, 1, true) then icon = word return end
                    end
                    local res = raw:match("^MI_UI_(%a+)") or raw:match("Dilithium") or raw:match("Deuterium")
                    if res then icon = res:lower() end
                end
            end)
            return
        end
        local ok, txt = pcall(function() return w:GetText():ToString() end)
        if ok and type(txt) == "string" then
            local t = require("text").prep(txt):gsub("<[^>]*>", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
            if t ~= "" then
                if t:match("^%d+$") and icon then t = t .. " " .. icon
                -- The game's own "14 remaining" in any language: a number
                -- and one word ("14 verbleibend" had no unit, firefly82's
                -- review, 2026-10-19). Icon numbers come bare, above.
                -- The game writes it "14 remaining ..." (read in the VM).
                elseif (t:gsub("%s*%.%.%.$", "")):match("^%d+ %S+$") then
                    local n, word = (t:gsub("%s*%.%.%.$", "")):match("^(%d+) (%S+)$")
                    t = n .. (n == "1" and " cycle " or " cycles ") .. word
                end
                out[#out + 1] = t
                icon = nil
            end
            return
        end
        if w:IsA(W) then
            local tree = w.WidgetTree
            if tree and tree:IsValid() and tree.RootWidget then walk(tree.RootWidget, depth + 1) end
        elseif w:IsA(PANEL) then
            for i = 0, w:GetChildrenCount() - 1 do walk(w:GetChildAt(i), depth + 1) end
        end
    end
    walk(view, 0)
    return out
end

local function view_text(view, start, abort)
    local name, costs, rest = nil, {}, {}
    for _, s in ipairs(view_texts(view)) do
        -- While researching: "16 remaining ...", "Researching ..."
        s = s:gsub("%s*%.%.%.$", "")
        if s:lower() == "research" then
        elseif not name then name = s
        elseif s:match("^%d+") then costs[#costs + 1] = s
        else rest[#rest + 1] = s end
    end
    local parts = { name or "Technology" }
    if #costs > 0 then parts[#parts + 1] = table.concat(costs, ", ") end
    for _, s in ipairs(rest) do parts[#parts + 1] = s end
    parts[#parts + 1] = start and "Enter begins the research, Escape closes"
        or abort and "Enter aborts the research, Escape closes" or "Escape closes"
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    return table.concat(parts, ". ") .. "."
end

local view_said = nil

-- The list item whose Enter opened the details view. The view stays open
-- while Up and Down move on, and Enter then pressed the open view's Start:
-- Bussard Collectors was announced and Plasma Torch began (firefly82's
-- review, reproduced in the VM, 2026-10-19). Enter on another item opens
-- that item's view instead.
local view_for = nil

local function press(b)
    b:HandleButtonPressed()
    b:HandleButtonReleased()
    b:HandleButtonClicked()
end

function M.enter()
    local view, start, abort = selected_view()
    local it = list.items[list.index]
    if view and it and it.button == view_for then
        if not (start or abort) then
            speech.say(view_text(view, nil), true)
            return
        end
        print("[VoyagerAccess] techtree: " .. (start and "begin" or "abort") .. " research\n")
        press(start or abort)
        ExecuteInGameThreadWithDelay(600, function()
            pcall(function()
                if list and refresh(true) then say(false) end
            end)
        end)
        return
    end
    local b = it and StaticFindObject(it.button)
    if not (b and b:IsValid()) then return end
    print("[VoyagerAccess] techtree: clicking " .. it.text .. "\n")
    view_for = it.button
    view_said = nil
    press(b)
    -- Its state can change (research started): read it again shortly,
    -- unless the details view opened (poll reads that).
    ExecuteInGameThreadWithDelay(600, function()
        pcall(function()
            if list and refresh(true) and not selected_view() then say(false) end
        end)
    end)
end

function M.switch_tab(dir)
    local name = dir < 0 and "PreviousTabButton" or "NextTabButton"
    for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
        if live(b) and b:GetFName():ToString() == name and b:GetFullName():find("TechTreeView", 1, true) then
            b:HandleButtonPressed()
            b:HandleButtonReleased()
            b:HandleButtonClicked()
        end
    end
    ExecuteInGameThreadWithDelay(400, function()
        pcall(function()
            if refresh(false) then
                speech.say(list.tab .. " tab", true)
                say(false)
            end
        end)
    end)
    return true
end

local function poll()
    -- A crash in the open tree left only "popups: scan" as the last crumb
    -- (Q Trial, VM, 2026-10-16), so this poll marks itself too.
    require("crumb").at("techtree: poll")
    local now = open_now()
    if now and not list then
        if refresh(false) then
            require("focus").park_focus()
            print("[VoyagerAccess] techtree: " .. #list.items .. " items\n")
            speech.say("Tech tree, " .. list.tab .. " tab. Up and Down move, Left and Right switch category, Enter researches, Escape closes.", true)
            say(false)
        end
    elseif not now and list then
        list = nil
    end
    if list then
        local view, start, abort = selected_view()
        if view then
            local text = view_text(view, start, abort)
            if text ~= view_said then
                view_said = text
                print("[VoyagerAccess] techtree: " .. text .. "\n")
                speech.say(text, true)
            end
        elseif view_said then
            -- Closed (Escape): say where the list is again.
            view_said = nil
            say(true)
        end
    end
end

function M.install()
    LoopInGameThreadWithDelay(300, function()
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] techtree error: " .. tostring(err) .. "\n") end
    end)
end

return M
