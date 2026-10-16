-- Space combat (first met 2026-10-14 in the Val Jean test fight). The game's
-- own keys work in combat (Space pause, 1 to 6 abilities, E targeting,
-- arrows for energy), but nothing on the screen is a focusable button, and
-- the panels are numbers beside pictures. Read live:
--   * WBP_CombatMainWidget: PlayerView and EnemyView (ShipNameText,
--     T_HullIntegrity "240 / 400", Shield_Front/Back/Left/Right.TXT_SHIELD),
--     txt_selectedManeuver ("ATTACK  //"), FireControlWidget.CT_TorpedoAmmo,
--     WBP_CombatObjectives.EndingConditionText, and WBP_InfoPanel's
--     button_open_radial (a plain Button: ORDERS, which opens the order
--     wheel, a WBP_RadialMenu);
--   * WBP_SubsystemResponsive, one per subsystem of both ships, top-level
--     widgets: SubsystemNameText, CurrentHealth, MaxHealth, MySubsystem
--     (its outer is the ship actor);
--   * the wheel's Offensive Actions page: WBP_RadialButtonCombatOffensive,
--     icon only, with hoverText ("Weapons") and hp ("30").

local screen = require("screen")
local speech = require("speech")

local M = {}

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

local function live(o)
    return o and o:IsValid() and o:GetFullName():find(" /Engine/Transient.", 1, true) ~= nil
end

local function text_of(w)
    if not (w and w:IsValid()) then return "" end
    local ok, s = pcall(function() return w:GetText():ToString() end)
    return ok and s or ""
end

local function plain(s)
    s = require("text").prep(s)  -- icons beside numbers, list line breaks (text.lua)
    return (s:gsub("<[^>]*>", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function main()
    for _, w in ipairs(FindAllOf("WBP_CombatMainWidget_C") or {}) do
        if live(w) and screen.shown(w) then return w end
    end
    return nil
end

-- The combat screen is up at all, the hero setup included (system.lua keeps
-- travel lines quiet over it; VM, 2026-10-14).
function M.screen_up()
    return main() ~= nil
end

-- In battle: the combat screen is up and the hero setup before it is gone.
function M.active()
    local w = main()
    if not w then return false end
    local ok, L = pcall(function() return w.HeroLoadout end)
    if ok and L and L:IsValid() and screen.shown(L) then return false end
    -- Over once the result is up (the target kept being read after it).
    local okr, R = pcall(function() return w.CombatResultView end)
    if okr and R and R:IsValid() and screen.shown(R) then return false end
    return true
end

local function title(s)
    return (s:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end):gsub("U%.s%.s%.", "U.S.S."))
end

local function shields(view)
    local vals = {}
    -- Named as the order wheel names them (Defend Bow, Aft, Port, Starboard).
    local WORD = { Front = "bow", Back = "aft", Left = "port", Right = "starboard" }
    for _, side in ipairs({ "Front", "Back", "Left", "Right" }) do
        local ok, w = pcall(function() return view["Shield_" .. side] end)
        local v = ok and w and w:IsValid() and plain(text_of(w.TXT_SHIELD)) or ""
        if v ~= "" then vals[#vals + 1] = { side = WORD[side], v = v } end
    end
    if #vals == 0 then return nil end
    local same = true
    for _, s in ipairs(vals) do if s.v ~= vals[1].v then same = false end end
    if same then return "shields " .. vals[1].v .. " on every side" end
    local out = {}
    for _, s in ipairs(vals) do out[#out + 1] = s.side .. " " .. s.v end
    return "shields " .. table.concat(out, ", ")
end

-- The widget above w, crossing from a widget tree to the widget that owns it.
local USER_WIDGET = nil
local function up_one(w)
    local parent = w:GetParent()
    if parent and parent:IsValid() then return parent end
    USER_WIDGET = USER_WIDGET or StaticFindObject("/Script/UMG.UserWidget")
    local tree = w:GetOuter()
    local owner = tree and tree:IsValid() and tree:GetOuter()
    if owner and owner:IsValid() and owner:IsA(USER_WIDGET) then return owner end
    return nil
end

-- The subsystem lines shown inside a ship panel (PlayerView or EnemyView).
-- The panel's own widgets, not the ship actors: the enemy panel follows the
-- target, and an allied Maquis ship also had subsystems in the Kazon fight
-- (2026-10-14). The subsystem object is checked valid before it is used:
-- reading one the battle had destroyed (the Val Jean's shield generator)
-- stopped the mod's Lua (2026-10-14).
local function panel_subsystems(view)
    if not (view and view:IsValid()) then return nil end
    local target = path_of(view)
    local out = {}
    for _, x in ipairs(FindAllOf("WBP_SubsystemResponsive_C") or {}) do
        if live(x) then
            pcall(function()
                local node, inside = x, false
                for _ = 1, 40 do
                    node = up_one(node)
                    if not node then break end
                    if path_of(node) == target then inside = true break end
                end
                if not inside then return end
                local s = x.MySubsystem
                if not (s and s:IsValid()) then return end
                local name = plain(text_of(x.SubsystemNameText))
                if name == "" then return end
                local cur, max = math.floor((x.CurrentHealth or 0) + 0.5), math.floor((x.MaxHealth or 0) + 0.5)
                out[#out + 1] = string.format("%s %d of %d", name, cur, max)
            end)
        end
    end
    return #out > 0 and out or nil
end

local function ship_line(view, subs)
    if not (view and view:IsValid()) then return nil end
    local parts = { title(plain(text_of(view.ShipNameText))) }
    local hull = plain(text_of(view.T_HullIntegrity)):gsub("%s*/%s*", " of ")
    if hull ~= "" then parts[#parts + 1] = "hull " .. hull end
    local sh = shields(view)
    if sh then parts[#parts + 1] = sh end
    if subs then parts[#parts + 1] = table.concat(subs, ", ") end
    return table.concat(parts, ", ")
end

function M.objective()
    local w = main()
    if not w then return nil end
    -- The demo's goal is EndingConditionText; a Q Trial battle's is
    -- OptionalConditionText ("Defeat the enemy"), and O said "No objective
    -- shown" (VM, 2026-10-14). All three, in that order, when shown.
    local out = {}
    for _, name in ipairs({ "EndingConditionText", "RequiredConditionText", "OptionalConditionText" }) do
        local ok, t = pcall(function() return w.WBP_CombatObjectives[name] end)
        if ok and t and t:IsValid() and screen.shown(t) then
            local s = plain(text_of(t))
            if s ~= "" then out[#out + 1] = s end
        end
    end
    -- The demo's EndingConditionText was read without a shown check.
    if #out == 0 then
        local ok, t = pcall(function() return w.WBP_CombatObjectives.EndingConditionText end)
        local s = ok and plain(text_of(t)) or ""
        if s ~= "" then out[1] = s end
    end
    return #out > 0 and table.concat(out, ". ") or nil
end

local function seconds(t)
    local n = math.ceil(t)
    return n .. (n == 1 and " second" or " seconds")
end

-- The heroes' abilities on keys 1 to 3 (WBP_ExtAbility: Index, Ability
-- with AbilityName, HeroID, CooldownLeft, ActiveTimeLeft), seen
-- 2026-10-14 as Evasive Maneuver, Rousing Speech, Phaser Double Damage.
function M.abilities()
    local list = {}
    -- Not checked as shown: screen.shown said no while they were on screen.
    for _, x in ipairs(FindAllOf("WBP_ExtAbility_C") or {}) do
        if live(x) then
            pcall(function()
                local ab = x.Ability
                if not (ab and ab:IsValid()) then return end
                local name = plain(ab.AbilityName:ToString())
                local hero = ab.HeroID:ToString():gsub("^Char_", ""):gsub("_", " ")
                local state = "ready"
                if (ab.ActiveTimeLeft or 0) > 0 then
                    state = "active, " .. seconds(ab.ActiveTimeLeft) .. " left"
                elseif (ab.CooldownLeft or 0) > 0 then
                    state = "ready in " .. seconds(ab.CooldownLeft)
                end
                list[#list + 1] = { i = x.Index, text = string.format("%d, %s, %s, %s", x.Index + 1, name, hero, state) }
            end)
        end
    end
    table.sort(list, function(a, b) return a.i < b.i end)
    local out = {}
    for _, it in ipairs(list) do out[#out + 1] = it.text end
    return #out > 0 and ("Abilities: " .. table.concat(out, "; ")) or nil
end

-- "Combat is paused! Complete Tutorial Steps to Continue" (or "Toggle
-- Pause"): TextBlock and TextBlock_1 in the combat window's own tree.
function M.paused_text(w)
    w = w or main()
    if not w then return nil end
    local prefix = path_of(w) .. "."
    local by = {}
    for _, t in ipairs(FindAllOf("TextBlock") or {}) do
        local tp = t:IsValid() and path_of(t)
        if tp and tp:sub(1, #prefix) == prefix then
            -- Found by its words: the full game names them TextBlock_69 and
            -- CombatPauseText, the demo TextBlock and TextBlock_1 (VM,
            -- 2026-10-14: a Q Trial battle paused without a word).
            local name = tp:sub(#prefix + 1):match("^WidgetTree_%d+%.([%w_]+)$")
            if name and screen.shown(t) then
                local s = plain(text_of(t))
                if s:lower():find("^combat is paused") then by.head = s
                elseif s ~= "" and (name == "TextBlock_1" or name == "CombatPauseText") then by.detail = s end
            end
        end
    end
    if not by.head then return nil end
    local s = by.head:gsub("!$", "")
    if by.detail and by.detail ~= "Toggle Pause" then s = s .. ". " .. by.detail end
    return s
end

-- The enemy list beside the target panel (WBP_TGT_ENTRY: TGT_Name, and
-- selected_border on the targeted one), e.g. the Kazon Carrier with Support
-- Vessels Alpha and Beta. Tab moves the target through it.
function M.enemies()
    local names = {}
    for _, e in ipairs(FindAllOf("WBP_TGT_ENTRY_C") or {}) do
        if live(e) and screen.shown(e) then
            pcall(function()
                local n = plain(text_of(e.TGT_Name))
                if n == "" then return end
                if screen.shown(e.selected_border) then n = n .. ", targeted" end
                names[#names + 1] = n
            end)
        end
    end
    if #names < 2 then return nil end
    return "Enemies: " .. table.concat(names, "; ")
end

-- L in combat: both ships, the current order, torpedoes and the goal.
function M.status()
    local w = main()
    if not w then return nil end
    local parts = {}
    local mine = ship_line(w.PlayerView, panel_subsystems(w.PlayerView))
    if mine then parts[#parts + 1] = mine end
    local theirs = ship_line(w.EnemyView, panel_subsystems(w.EnemyView))
    if theirs then parts[#parts + 1] = "Target: " .. theirs end
    local enemies = M.enemies()
    if enemies then parts[#parts + 1] = enemies end
    local order = plain(text_of(w.txt_selectedManeuver)):gsub("%s*/+%s*$", ""):gsub("%s*/+%s*", ", ")
    -- "ATTACK // Right": the side as bow, aft, port or starboard, as the
    -- shields are read (VM, 2026-10-14).
    local SIDES = { Right = "starboard", Left = "port", Front = "bow", Back = "aft", Rear = "aft" }
    order = order:gsub(", (%a+)$", function(s) return SIDES[s] and (", " .. SIDES[s]) or nil end)
    if order ~= "" then parts[#parts + 1] = "Order: " .. title(order) end
    local okt, ammo = pcall(function() return plain(text_of(w.FireControlWidget.CT_TorpedoAmmo)) end)
    if okt and ammo ~= "" then parts[#parts + 1] = ammo .. " torpedoes" end
    local abilities = M.abilities()
    if abilities then parts[#parts + 1] = abilities end
    local goal = M.objective()
    if goal then parts[#parts + 1] = "Goal: " .. goal end
    local paused = M.paused_text(w)
    if paused then parts[#parts + 1] = paused end
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    return table.concat(parts, ". ") .. "."
end

-- The order wheel's buttons that show only a picture.
function M.handles(b, path)
    local cls = b:GetClass():GetFName():ToString()
    if cls == "WBP_RadialButtonCombatOffensive_C" then return true end
    return path:find("WBP_RadialMenu_C_%d+%.WidgetTree_%d+%.BackButton$") ~= nil and M.active()
end

function M.button_label(b, path)
    if path:find("%.BackButton$") then return "Back" end
    local prefix = path .. "."
    local by = {}
    for _, t in ipairs(FindAllOf("TextBlock") or {}) do
        local tp = t:IsValid() and path_of(t)
        if tp and tp:sub(1, #prefix) == prefix then
            local name = tp:match("([^%.]+)$")
            if not by[name] then by[name] = plain(text_of(t)) end
        end
    end
    local label = by.hoverText ~= "" and by.hoverText or "Subsystem"
    if by.hp and by.hp ~= "" then label = label .. ", " .. by.hp .. " health" end
    return label
end

-- ORDERS is a plain Button with no keyboard path: Enter in battle, with no
-- wheel open, runs the panel's own click event. (Its geometry read back as
-- 0 by 0 through UE4SS, so a mouse click could not be aimed, 2026-10-14.)
function M.open_orders()
    local w = main()
    if not w then return false end
    local ok, err = pcall(function()
        w.WBP_InfoPanel:BndEvt__WBP_InfoPanel_Button_84_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature()
    end)
    print("[VoyagerAccess] combat: open Orders " .. (ok and "done" or ("failed: " .. tostring(err))) .. "\n")
    return ok
end

local said_goal = nil

-- Keys 1 to 3 are the game's, so the mod hears nothing of them: say when an
-- ability turns active, and when one is ready again.
local ability_state = {}

local function abilities_poll()
    for _, x in ipairs(FindAllOf("WBP_ExtAbility_C") or {}) do
        if live(x) then
            pcall(function()
                local ab = x.Ability
                if not (ab and ab:IsValid()) then return end
                local key = path_of(ab)
                local state = "ready"
                if (ab.ActiveTimeLeft or 0) > 0 then state = "active"
                elseif (ab.CooldownLeft or 0) > 0 then state = "cooldown" end
                local was = ability_state[key]
                ability_state[key] = state
                if was and was ~= state and state ~= "cooldown" then
                    local text = string.format("%s %s", plain(ab.AbilityName:ToString()), state)
                    print("[VoyagerAccess] combat: " .. text .. "\n")
                    speech.say(text, false)
                end
            end)
        end
    end
end

-- Tab (the game's) changes the target: say the new one with its hull.
local said_target = nil

local function target_poll(w)
    local ok, key, name, hull = pcall(function()
        local v = w.EnemyView
        local c = v.MyCombatant
        local k = c and c:IsValid() and c:GetFName():ToString() or plain(text_of(v.ShipNameText))
        local h = plain(text_of(v.T_HullIntegrity)):gsub("%s*/%s*", " of ")
        return k, title(plain(text_of(v.ShipNameText))), h
    end)
    if not ok or not key or name == "" then return end
    if said_target and key ~= said_target then
        local text = "Target: " .. name .. (hull ~= "" and (", hull " .. hull) or "")
        print("[VoyagerAccess] combat: " .. text .. "\n")
        speech.say(text, true)
    end
    said_target = key
end

-- Space (the game's) pauses and resumes without a word; tutorial steps
-- pause it too.
local said_pause = false

local function pause_poll(w)
    local p = M.paused_text(w)
    if p and p ~= said_pause then
        print("[VoyagerAccess] combat: " .. p .. "\n")
        speech.say(p, false)
    elseif not p and said_pause then
        speech.say("Combat resumed", false)
    end
    said_pause = p or false
end

-- The battle setup (HeroLoadout): Start Combat (HeroLoadout.ProceedButton)
-- has CommonUI's "Start" input action, so Enter anywhere on the setup
-- pressed Start Combat, whichever button had focus. Enter on Auto Resolve,
-- Surrender or a hero slot started the fight, and with the mod's click as
-- well it jammed half in setup and half in battle (VM, 2026-10-15; the
-- button's TriggeringInputAction row is "Start", and taking the combat input
-- map away did not stop it). While focus is on another setup button the
-- action is taken off Start Combat, so Enter does only what that button
-- does; on Start Combat, and when the setup closes, it is put back, so
-- starting a battle stays the game's own Enter. focus.lua calls sync on
-- every focus change (the game acts on Enter before the mod hears it).
local taken = nil   -- { path, dt, row } while the action is off the button

local function start_button()
    local w = main()
    local ok, b = pcall(function() return w.HeroLoadout.ProceedButton end)
    return ok and b and b:IsValid() and b or nil
end

function M.result_up()
    local w = main()
    if not w then return false end
    local ok, R = pcall(function() return w.CombatResultView end)
    return ok and R and R:IsValid() and screen.shown(R) or false
end

function M.setup_up()
    local w = main()
    if not w then return false end
    local ok, L = pcall(function() return w.HeroLoadout end)
    if ok and L and L:IsValid() and screen.shown(L) then return true end
    -- Auto Resolve's window belongs to the setup (VM, 2026-10-15).
    local oka, A = pcall(function() return w.AutoResolveWidget end)
    return oka and A and A:IsValid() and screen.shown(A) or false
end

local function put_back(why)
    local g = taken
    taken = nil
    local b = g and StaticFindObject(g.path)
    if b and b:IsValid() then
        local ok = pcall(function() b:SetTriggeringInputAction({ DataTable = g.dt, RowName = FName(g.row) }) end)
        print("[VoyagerAccess] combat: " .. why .. ", " .. g.row .. (ok and " put back" or " NOT put back") .. "\n")
    end
end

function M.setup_sync()
    local up = main() and M.setup_up()
    local path = require("focus").current_path() or ""
    local on_start = path:find("HeroLoadout%.WidgetTree_%d+%.ProceedButton$") ~= nil
    if up and not on_start and not taken then
        local b = start_button()
        if not b then return end
        local ok, row = pcall(function() return b.TriggeringInputAction.RowName:ToString() end)
        if not ok or row == "None" then return end
        local okd, dt = pcall(function() return b.TriggeringInputAction.DataTable end)
        if pcall(function() b:SetTriggeringInputAction({ DataTable = nil, RowName = FName("None") }) end) then
            taken = { path = b:GetFullName():match("^%S+%s+(.+)$"), dt = okd and dt or nil, row = row }
            print("[VoyagerAccess] combat: setup, Enter no longer starts the battle (" .. row .. " taken off)\n")
        end
    elseif taken and (not up or on_start) then
        put_back(up and "focus on Start Combat" or "setup closed")
    end
end

local function poll()
    M.setup_sync()
    if not M.active() then said_goal = nil said_target = nil said_pause = false ability_state = {} return end
    abilities_poll()
    target_poll(main())
    pause_poll(main())
    local goal = M.objective()
    if goal and goal ~= said_goal then
        said_goal = goal
        print("[VoyagerAccess] combat goal: " .. goal .. "\n")
        speech.say("Combat goal: " .. goal, false)
    end
end

function M.install()
    LoopInGameThreadWithDelay(500, function()
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] combat error: " .. tostring(err) .. "\n") end
    end)
end

return M
