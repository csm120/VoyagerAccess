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
--
-- Past the last category (and before the first) Left and Right reach one
-- more list, every category's technologies from A to Z (TheRev on the
-- forum: finding one technology meant guessing its category; Casey agreed,
-- 2026-10-20). It is built by showing each tab in turn, so it has only what
-- the tabs show. Enter goes to the item in its own category and opens it.

local speech = require("speech")
local screen = require("screen")

local M = {}

local list = nil    -- { items = { {text, button path} }, index, tab, az }
local building = false   -- the A to Z list is being gathered tab by tab

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

-- The tree's own widget (WBP_TechTreeView_C in the HUD), set when its class
-- is first seen (hook_view below). Everything the tree shows is read from
-- its fields (TierButtons, GridWidgets, TechTreeButtons, SelectedTechView),
-- not by searching every widget of a class (Audit-Technologiebaum-Oeffnen,
-- 2026-10-21).
local view_path = nil
local function tree_view()
    local v = view_path and StaticFindObject(view_path)
    if v and v:IsValid() then return v end
    return nil
end

-- On screen inside the tree. The tree's parents are left out: the game's
-- window stack still plays its fade while the tree is open and built, and
-- for those ticks the stack shows the page before it (tree audit
-- 2026-10-21: IsTechTreeOpen true, OverlaySwitcher in transition), so a
-- check up to the screen said nothing was there and the tree was never read.
local function in_tree(w, v)
    return w and w:IsValid() and screen.shown(w, v or tree_view()) or false
end

-- The game's own state, not "is a button visible": USTVUISubsystem knows
-- whether the tree is open (true from the tick after BP_OnActivated).
local ui = nil
local function open_now()
    if not (ui and ui:IsValid()) then ui = FindFirstOf("STVUISubsystem") end
    if not (ui and ui:IsValid()) then return false end
    local ok, open = pcall(function() return ui:IsTechTreeOpen() end)
    return ok and open == true and tree_view() ~= nil
end

-- The used entries of one of the tree's widget lists, valid ones only.
local function used(arr, n)
    local out = {}
    pcall(function()
        local count = #arr
        if n and n < count then count = n end
        for i = 1, count do
            local w = arr[i]
            if w and w:IsValid() then out[#out + 1] = w end
        end
    end)
    return out
end

local function state(researched, can, current)
    if current then return "researching" end
    if researched then return "researched" end
    if can then return "available" end
    return "locked"
end

-- The category tabs' buttons, from the tree's TechTreeButtons.
local function tab_buttons()
    local v = tree_view()
    if not v then return {} end
    local out = {}
    local n = nil
    pcall(function() n = v.NumTechTreeButtonsUsed end)
    for _, t in ipairs(used(v.TechTreeButtons, n)) do
        local b = nil
        pcall(function() b = t.WBP_CommonButton_RoomMgmt_V2 end)
        if b and b:IsValid() and in_tree(b, v) then out[#out + 1] = b end
    end
    return out
end

local function tab_name()
    for _, b in ipairs(tab_buttons()) do
        local ok, sel = pcall(function() return b:GetSelected() end)
        if ok and sel then
            local okn, s = pcall(function() return b.ButtonName:GetText():ToString() end)
            if okn and s ~= "" then return s end
        end
    end
    return "Tech tree"
end

-- The category tabs in their order on screen.
local function tabs()
    local out = {}
    for _, b in ipairs(tab_buttons()) do
        do
            local t = { path = path_of(b), name = "", selected = false, idx = 0 }
            pcall(function() t.name = b.ButtonName:GetText():ToString() end)
            pcall(function() t.selected = b:GetSelected() == true end)
            pcall(function() t.idx = b.Slot.Parent:GetChildIndex(b) end)
            out[#out + 1] = t
        end
    end
    table.sort(out, function(a, b) return a.idx < b.idx end)
    return out
end

-- The game's names wrap inside the field: a line break after a hyphen joins
-- the word, any other is a space, and a zero-width space goes (firefly82's
-- review, 2026-10-19: "Deuterium-Abfall- reduzierung"). Before a lowercase
-- letter the hyphen only broke the word for the layout and goes too
-- ("Verhandlungs-taktiken", VM, 2026-10-20); before a capital it is real.
-- Lowercase here is ASCII or a Latin-1 letter (UTF-8 C3 A0 to C3 BF).
local function clean_name(s)
    s = s:gsub("%-[ \t]*\r?\n%s*(%l)", "%1"):gsub("%-[ \t]*\r?\n%s*(\195[\160-\191])", "%1")
    return (s:gsub("%-[ \t]*\r?\n%s*", "-"):gsub("%s*\r?\n%s*", " "):gsub("\226\128\139", ""))
end

-- The lines on screen between technologies are the data's PrecursorTechs
-- (firefly82, tested on the Crew tab, 2026-10-19). The shown category is
-- the STVTechTree whose techs sit at the shown widgets' places (Tier is the
-- grid row, TierSlot the column; VM, 2026-10-19). For each place, the
-- places of the techs it builds on.
local function precursors_by_place(shown)
    local best, best_n = nil, 0
    for _, t in ipairs(FindAllOf("STVTechTree") or {}) do
        if t:IsValid() and not t:GetFullName():find("Default__", 1, true) then
            local n = 0
            pcall(function()
                for i = 1, #t.Techs do
                    local e = t.Techs[i]
                    local w = shown[e.Tier .. ":" .. e.TierSlot]
                    if w and not w.obf and w.name == clean_name(e.Name:ToString()) then n = n + 1 end
                end
            end)
            if n > best_n then best, best_n = t, n end
        end
    end
    local out = {}
    if not best then return out end
    pcall(function()
        local place = {}
        for i = 1, #best.Techs do
            local e = best.Techs[i]
            place[e.NameTag.TagName:ToString()] = e.Tier .. ":" .. e.TierSlot
        end
        for i = 1, #best.Techs do
            local e = best.Techs[i]
            local list = {}
            local tags = e.PrecursorTechs.GameplayTags
            for j = 1, #tags do
                local p = place[tags[j].TagName:ToString()]
                if p then list[#list + 1] = p end
            end
            out[e.Tier .. ":" .. e.TierSlot] = list
        end
    end)
    return out
end

local function build()
    local items = {}
    local tiers = {}
    local v = tree_view()
    if not v then return items end
    for _, w in ipairs(used(v.TierButtons)) do
        if in_tree(w, v) then
            -- The tier's number, in its button's own TextBlock.
            local n = ""
            pcall(function() n = w.TierButton.TextBlock:GetText():ToString() end)
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
    local n_used = nil
    pcall(function() n_used = v.NumGridWidgetsUsed end)
    for _, w in ipairs(used(v.GridWidgets, n_used)) do
        if in_tree(w.RegularTechButton, v) then
            local row, col = 0, 0
            pcall(function() row, col = w.Slot.Row, w.Slot.Column end)
            local name = ""
            pcall(function() name = clean_name(w.TechName:ToString()) end)
            local obf = w.bObfuscate == true or name == ""
            if obf then name = "Unknown technology" end
            -- Row 0 is the starting technologies, above the Tier 1 band;
            -- row N is tier N. "row + 1" called Hyperspanner tier 3 while it
            -- sits in the Tier 2 band (VM screenshot, 2026-10-15).
            local st = state(w.bAlreadyResearched, w.bCanBeresearchItem, w.bCurrentResearch)
            local where = row == 0 and "starting technology" or ("tier " .. row)
            -- A tech in a tier not yet researched is locked by that tier.
            if st == "locked" and row > 0 and tier_done[row] == false then st = "locked until its tier is researched" end
            techs[#techs + 1] = {
                row = row, col = col, name = name, obf = obf,
                text = string.format("%s, %s, %s", name, where, st),
                button = path_of(w.RegularTechButton),
                -- Shown as a style and an icon on the field (firefly82).
                important = not obf and w.bImportant == true,
                feature = not obf and w.bUnlocksFeature == true,
            }
        end
    end
    -- What each one builds on, as the lines show it: only technologies the
    -- screen shows, an obfuscated one as "an unknown technology".
    local shown = {}
    for _, t in ipairs(techs) do shown[t.row .. ":" .. t.col] = t end
    local okp, pre = pcall(precursors_by_place, shown)
    for _, t in ipairs(techs) do
        local names, unknown = {}, 0
        for _, p in ipairs((okp and pre[t.row .. ":" .. t.col]) or {}) do
            local s = shown[p]
            if s and s.obf then unknown = unknown + 1 elseif s then names[#names + 1] = s.name end
        end
        if unknown > 0 then names[#names + 1] = unknown == 1 and "an unknown technology" or (unknown .. " unknown technologies") end
        -- Filled here in the game's language: left to the line pass, its
        -- last slot took the rest of the line, and German said "baut auf
        -- Messe, 12 von 48 auf" (firefly82, 2026-10-21).
        if #names > 0 then t.text = t.text .. require("tr").fill(", builds on {s}", table.concat(names, require("tr").word(" and "))) end
        if t.important then t.text = t.text .. ", important" end
        if t.feature then t.text = t.text .. ", unlocks a feature" end
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
    local tv = tree_view()
    local v = nil
    pcall(function() v = tv.SelectedTechView end)
    if not in_tree(v, tv) then return nil end
    local start, abort = nil, nil
    pcall(function() start = v.StartResearchButton end)
    pcall(function() abort = v.AbortResearchButton end)
    if not in_tree(start, tv) then start = nil end
    if not in_tree(abort, tv) then abort = nil end
    return v, start, abort
end

-- A technology's panel is open, or was until a moment ago (focus.lua:
-- Escape closes it, not the tree). The game's Escape closes the panel
-- before the mod's key handler runs, so a panel last said open, or closed
-- within a second, still counts.
-- (M.panel_open is below view_said.)
local panel_closed_at = -100

-- Its numbers have no words, only an icon before each (Cycle,
-- SciencePoints, Dilithium): the walk keeps the last icon's name. The
-- brush is checked valid before it is read (an unchecked read crashed the
-- game, 2026-10-11).
local ICONS = { Cycle = "cycles", SciencePoints = "research points" }

-- "cycles" in the game's language: the English word went into the German
-- text ("14 cycles verbleibend", firefly82's review, 2026-10-20). The
-- game's own lowercase "cycles" text (empty namespace; German "Zyklen"),
-- with English's singular kept.
local function cycles_word(n)
    if require("language").english() then return n == "1" and "cycle" or "cycles" end
    local word = "cycles"
    pcall(function()
        local out = {}
        local lib = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
        if lib:FindTextInLocalizationTable("", "51E1BB5148FBCDD4B50B4D95F07DFCE1", out, "") then
            local s = out.OutText:ToString()
            if s ~= "" then word = s end
        end
    end)
    return word
end

local function view_texts(view)
    local W = StaticFindObject("/Script/UMG.UserWidget")
    local PANEL = StaticFindObject("/Script/UMG.PanelWidget")
    local BTN = StaticFindObject("/Script/CommonUI.CommonButtonBase")
    local IMG = StaticFindObject("/Script/UMG.Image")
    local out, icon = {}, nil
    local function walk(w, depth)
        if depth > 40 or not (w and w:IsValid()) or not in_tree(w) then return end
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
                if t:match("^%d+$") and icon then
                    -- In the game's language outside English (firefly82's
                    -- review, 2026-10-20: "18 cycles, 100 research points").
                    local word = icon
                    if not require("language").english() then
                        if icon == "cycles" then word = cycles_word(t)
                        else
                            local id = icon == "research points" and "SciencePoints" or (icon:gsub("^%l", string.upper))
                            word = require("text").game_resource_name(id) or icon
                        end
                    end
                    t = t .. " " .. word
                -- The game's own "14 remaining" in any language: a number
                -- and one word ("14 verbleibend" had no unit, firefly82's
                -- review, 2026-10-19). Icon numbers come bare, above.
                -- The game writes it "14 remaining ..." (read in the VM).
                elseif (t:gsub("%s*%.%.%.$", "")):match("^%d+ %S+$") then
                    local n, word = (t:gsub("%s*%.%.%.$", "")):match("^(%d+) (%S+)$")
                    t = n .. " " .. cycles_word(n) .. " " .. word
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
    -- The name from the panel's own TechNameTextBlock: in German the
    -- heading "Forschung" was taken as the name and the real one came after
    -- the costs (firefly82's review, 2026-10-23). Texts before the name that
    -- are not costs are the heading, in any language.
    local field_name = ""
    pcall(function()
        local t = view.TechNameTextBlock
        if t and t:IsValid() then field_name = (t:GetText():ToString():gsub("<[^>]*>", ""):gsub("^%s+", ""):gsub("%s+$", "")) end
    end)
    local texts = view_texts(view)
    local at = nil
    if field_name ~= "" then
        for i, s in ipairs(texts) do if s == field_name then at = i break end end
    end
    local name, costs, rest = nil, {}, {}
    for i, s in ipairs(texts) do
        -- While researching: "16 remaining ...", "Researching ..."
        s = s:gsub("%s*%.%.%.$", "")
        if at and i < at and not s:match("^%d+") then
        elseif at and i == at then name = s
        elseif not at and s:lower() == "research" then
        elseif not name and not at then name = s
        elseif s:match("^%d+") then costs[#costs + 1] = s
        else rest[#rest + 1] = s end
    end
    -- An unrevealed one shows "???"; the list calls it what it is.
    if name and not name:find("[%w\128-\255]") then name = "Unknown technology" end
    local parts = { name or "Technology" }
    -- The lock a sighted player sees on the panel (Locked_Image).
    pcall(function()
        local l = view.Locked_Image
        if l and l:IsValid() and require("screen").shown(l) then parts[#parts + 1] = require("tr").word("Locked") end
    end)
    if #costs > 0 then parts[#parts + 1] = table.concat(costs, ", ") end
    for _, s in ipairs(rest) do parts[#parts + 1] = s end
    parts[#parts + 1] = start and "Enter begins the research, Escape closes"
        or abort and "Enter aborts the research, Escape closes" or "Escape closes"
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    return table.concat(parts, ". ") .. "."
end

local view_said = nil

function M.panel_open()
    local ok, v = pcall(selected_view)
    return (ok and v ~= nil) or view_said ~= nil or os.clock() - panel_closed_at < 1
end

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

-- The view's own PostRefreshGrid runs when its grid has been rebuilt (a
-- tab shown): read then, not after a fixed wait (firefly82's review,
-- 2026-10-20). A pre callback, so the grid is read on the next tick. The
-- hook goes in when the tree is first seen open (poll below), before any
-- key can ask for it; there is no timer behind it any more (firefly82's
-- review, 2026-10-21: the 800 and 900 ms "safety net" read whatever the
-- grid showed then).
local GRID_HOOK = "/Game/STVoyager/Tech/UI/WBP_TechTreeView.WBP_TechTreeView_C:PostRefreshGrid"
local grid_hooked = false
local grid_waiters = {}

local function ensure_grid_hook()
    if grid_hooked or not StaticFindObject(GRID_HOOK) then return end
    grid_hooked = pcall(RegisterHook, GRID_HOOK, function()
        ExecuteInGameThread(function()
            local list0 = grid_waiters
            grid_waiters = {}
            for _, w in ipairs(list0) do w() end
            -- The tree's grid is built: a tree just opened is read now. At
            -- its BP_OnActivated the tier buttons were not there yet, and the
            -- tree was never read (firefly82's test, 2026-10-21; the probe
            -- showed PostRefreshGrid right after BP_OnActivated).
            if not list and M.request_look then M.request_look() end
        end)
    end)
    print("[VoyagerAccess] techtree: grid hook " .. (grid_hooked and "installed" or "not installed") .. "\n")
end

-- fn once the grid has refreshed. 0.3.70 also ran it after 1.5 s without a
-- refresh, for three cases that left the A to Z list "building" for good
-- (review of firefly82's patch, 2026-10-21); each has its own answer now,
-- with no timer (review of 0.3.70, 2026-10-22):
-- - a tab already shown is not clicked (show_tab asks its GetSelected);
-- - the tree closed mid-build: its BP_OnDeactivated runs the waiters
--   (hook_view), and the build ends there (open_now() is false);
-- - the hook missing: fn runs at once, as the ship view does without its
--   hover hook. The grid class is loaded whenever the tree is, so this is
--   logged, not expected.
local function after_grid(fn)
    pcall(ensure_grid_hook)
    local ran = false
    local function run()
        if ran then return end
        ran = true
        local ok, err = pcall(fn)
        if not ok then print("[VoyagerAccess] techtree: " .. tostring(err) .. "\n") end
    end
    -- A tree that is not open builds no grid: at once (the A to Z build
    -- then ends on its own open_now() check).
    if grid_hooked and open_now() then
        grid_waiters[#grid_waiters + 1] = run
        -- A backstop only, for a click the game ignored with the tree still
        -- open (no refresh, no close): without it the A to Z list stayed
        -- "building" (GPT review, 2026-10-22). Never runs twice (ran).
        ExecuteInGameThreadWithDelay(3000, function()
            if not ran then
                print("[VoyagerAccess] techtree: no grid refresh after 3 s, going on\n")
                run()
            end
        end)
    elseif grid_hooked then
        run()
    else
        print("[VoyagerAccess] techtree: grid hook missing, reading at once\n")
        run()
    end
end

-- The tree has closed: whatever waited for a grid refresh is told now.
local function release_waiters()
    local list0 = grid_waiters
    grid_waiters = {}
    for _, w in ipairs(list0) do w() end
end

-- Clicks a category tab and runs fn once its grid is shown. A tab already
-- shown is not clicked: nothing would be rebuilt, so no refresh would come.
local function show_tab(path, fn)
    local b = path and StaticFindObject(path)
    if not (b and b:IsValid()) then return false end
    local oks, sel = pcall(function() return b:GetSelected() == true end)
    if oks and sel then
        local ok, err = pcall(fn)
        if not ok then print("[VoyagerAccess] techtree: " .. tostring(err) .. "\n") end
        return true
    end
    after_grid(fn)
    press(b)
    return true
end

-- Shows each tab in turn, keeps its technologies (not the tiers), then
-- shows again the tab the player was on. done(items) or done(nil).
local function build_az(done)
    local ts = tabs()
    if #ts == 0 then return done(nil) end
    local back = nil
    for _, t in ipairs(ts) do if t.selected then back = t end end
    local items, i = {}, 0
    local function next_tab()
        if not open_now() then return done(nil) end
        i = i + 1
        local t = ts[i]
        if not t then
            if not (back and show_tab(back.path, function() done(items) end)) then done(items) end
            return
        end
        if not show_tab(t.path, function()
            local ok, err = pcall(function()
                for _, it in ipairs(build()) do
                    if it.row then
                        items[#items + 1] = {
                            name = it.name, row = it.row, col = it.col, tab = t.path,
                            text = it.name .. ", " .. t.name .. it.text:sub(#it.name + 1),
                        }
                    end
                end
            end)
            if not ok then print("[VoyagerAccess] techtree A to Z: " .. tostring(err) .. "\n") end
            next_tab()
        end) then next_tab() end
    end
    next_tab()
end

local function open_az()
    building = true
    speech.say("A to Z, every category", true)
    build_az(function(items)
        building = false
        if not (items and #items > 0 and list) then return end
        table.sort(items, function(a, b)
            local x, y = a.name:lower(), b.name:lower()
            if x ~= y then return x < y end
            return a.text < b.text
        end)
        list = { items = items, index = 1, tab = "A to Z", az = true }
        print("[VoyagerAccess] techtree: A to Z, " .. #items .. " items\n")
        say(false)
    end)
end

-- Enter in the A to Z list: shows the item's category, moves there and
-- opens the item as Enter in that category would.
local function az_enter()
    local it = list.items[list.index]
    if not it then return end
    building = true
    local shown = show_tab(it.tab, function()
        building = false
        pcall(function()
            if not refresh(false) then return end
            for i, x in ipairs(list.items) do
                if x.row == it.row and x.col == it.col and x.name == it.name then list.index = i end
            end
            M.enter()
        end)
    end)
    if not shown then building = false end
end

function M.enter()
    if building then return end
    if list.az then return az_enter() end
    local view, start, abort = selected_view()
    local it = list.items[list.index]
    if view and it and it.button == view_for then
        if not (start or abort) then
            speech.say(view_text(view, nil), true)
            return
        end
        print("[VoyagerAccess] techtree: " .. (start and "begin" or "abort") .. " research\n")
        press(start or abort)
        -- Beginning a research does not refresh the grid (VM, 2026-10-20);
        -- the game's research events bring the list up to date instead
        -- (research_changed, M.install), not a 600 ms wait.
        return
    end
    local b = it and StaticFindObject(it.button)
    if not (b and b:IsValid()) then return end
    print("[VoyagerAccess] techtree: clicking " .. it.text .. "\n")
    view_for = it.button
    view_said = nil
    press(b)
    -- If this began a research, the game's research event reads the
    -- technology again (research_changed); the details view, if it opened,
    -- is read by poll.
end

-- The game announces a research begun or stopped on its event bus, as a
-- new STVResearchStartedPayload or STVResearchCancelledPayload (event-bus
-- census, 2026-10-22). The list is brought up to date on the next tick,
-- when the payload has been sent. Without the details view the item is said
-- again; with it, the view already says "Researching", and the whole tier
-- line after it was noise (Q Trials, VM, 2026-10-21). Replaces two 600 ms
-- waits (review of 0.3.70, 2026-10-22). OPEN POINT: not yet seen in play.
local function research_changed()
    print("[VoyagerAccess] techtree: research event from the game\n")
    ExecuteInGameThread(function()
        pcall(function()
            if list and refresh(true) and not selected_view() then say(false) end
        end)
    end)
end

function M.switch_tab(dir)
    if building then return true end
    local ts = tabs()
    if list and list.az then
        -- Right goes on to the first category, Left back to the last.
        local t = dir > 0 and ts[1] or ts[#ts]
        if t then
            show_tab(t.path, function()
                pcall(function()
                    if refresh(false) then
                        speech.say(require("tr").fill("{s} tab", list.tab), true)
                        say(false)
                    end
                end)
            end)
        end
        return true
    end
    local cur = nil
    for i, t in ipairs(ts) do if t.selected then cur = i end end
    if cur and ((dir > 0 and cur == #ts) or (dir < 0 and cur == 1)) then
        open_az()
        return true
    end
    local name = dir < 0 and "PreviousTabButton" or "NextTabButton"
    after_grid(function()
        pcall(function()
            if refresh(false) then
                speech.say(require("tr").fill("{s} tab", list.tab), true)
                say(false)
            end
        end)
    end)
    local b = nil
    pcall(function() b = tree_view()[name] end)
    if b and b:IsValid() then press(b) end
    return true
end

local function poll()
    -- A crash in the open tree left only "popups: scan" as the last crumb
    -- (Q Trial, VM, 2026-10-16), so this poll marks itself too.
    require("crumb").at("techtree: poll")
    local now = open_now()
    if now and not list then
        pcall(ensure_grid_hook)
        if refresh(false) then
            require("focus").park_focus()
            print("[VoyagerAccess] techtree: " .. #list.items .. " items\n")
            speech.say("Tech tree, " .. list.tab .. " tab." .. require("hints").text("tree_keys", " Up and Down move, Left and Right switch category, Enter researches, Escape closes."), true)
            say(false)
        else
            -- The game says the tree is open and its fields gave nothing:
            -- the code cannot tell why, so the log says it.
            print("[VoyagerAccess] techtree: open, but no tier or technology read\n")
        end
    elseif not now and list then
        list = nil
        -- Closing the tree said nothing; the ship view or map behind it is
        -- said again (VM, 2026-10-21).
        pcall(function() require("help").view_again() end)
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
            panel_closed_at = os.clock()
            say(true)
        end
    end
end

-- Looked at when the tree tells something changed, not every 300 ms (the
-- mod's loops held the game long enough to swallow keys; firefly82,
-- 2026-10-21). The probe of 2026-10-21 showed WBP_TechTreeView_C calling
-- BP_OnActivated as it opens, PostRefreshGrid, HideTechDescription and
-- SetTabWidgetActive on a tab change, and ShowTechDescription when a
-- technology's panel opens; BP_OnDeactivated is hooked too. The player's
-- keys also ask for a look while the tree is open (Escape closing it, a
-- research begun). One look per tick however many ask.
local look_queued = false
local function request_look()
    if look_queued then return end
    look_queued = true
    ExecuteInGameThread(function()
        look_queued = false
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] techtree error: " .. tostring(err) .. "\n") end
    end)
end

M.request_look = request_look   -- for the grid hook above

local view_hooked = false
local function hook_view(path)
    local w = StaticFindObject(path)
    if not (w and w:IsValid()) then return end
    -- The live tree in the HUD, not a template.
    if path:find("^/Engine/Transient%.") then view_path = path end
    if view_hooked then return end
    local cpath = w:GetClass():GetFullName():match("^%S+%s+(.+)$")
    local got = {}
    for _, fn in ipairs({ "BP_OnActivated", "BP_OnDeactivated", "ShowTechDescription", "HideTechDescription" }) do
        if StaticFindObject(cpath .. ":" .. fn) and pcall(RegisterHook, cpath .. ":" .. fn, function()
            request_look()
            -- Closed: a tab click waiting for its grid gets none now.
            if fn == "BP_OnDeactivated" then ExecuteInGameThread(release_waiters) end
            -- The tree fades in for a few ticks after it opens; if that
            -- look and PostRefreshGrid's both came too early, it stayed
            -- silent until reopened (review of firefly82's patch,
            -- 2026-10-21). Two more looks, only if it has not been read.
            if fn == "BP_OnActivated" then
                for _, ms in ipairs({ 300, 1000 }) do
                    ExecuteInGameThreadWithDelay(ms, function() if not list then request_look() end end)
                end
            end
        end) then
            got[#got + 1] = fn
        end
    end
    view_hooked = #got > 0
    pcall(ensure_grid_hook)
    print("[VoyagerAccess] techtree: view events: " .. table.concat(got, ", ") .. "\n")
    request_look()
end

function M.install()
    require("popups").on_widget("WBP_TechTreeView_C", hook_view)
    for _, w in ipairs(FindAllOf("WBP_TechTreeView_C") or {}) do
        local p = w:IsValid() and w:GetFullName():match("^%S+%s+(.+)$")
        if p and p:find("^/Engine/Transient%.") then pcall(hook_view, p) break end
    end
    require("keys").on_any(function() if list then request_look() end end)
    for _, cls in ipairs({ "STVResearchStartedPayload", "STVResearchCancelledPayload" }) do
        local ok, err = pcall(NotifyOnNewObject, "/Script/STVoyager." .. cls, function() research_changed() end)
        print("[VoyagerAccess] techtree: " .. cls .. " " .. (ok and "watched" or ("not watched: " .. tostring(err))) .. "\n")
    end
end

return M
