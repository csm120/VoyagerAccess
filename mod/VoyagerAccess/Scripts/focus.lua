-- Speaks the focused button whenever keyboard/gamepad focus moves.
-- Proven 2026-10-10 on the main menu: arrow keys move Slate focus to a widget
-- INSIDE a CommonButtonBase, and CommonButtonBase:HandleFocusReceived never
-- fires, so this polls HasFocusedDescendants/HasKeyboardFocus on buttons.

local speech = require("speech")

local M = {}

local INTERVAL_MS = 100
-- Never keep a UObject across ticks: the game destroys widgets (menus close,
-- dialogue ends) and touching the stale object crashed UE4SS while wrapping
-- a garbage pointer (symbolized crash, 2026-10-10 21:55). Keep paths and
-- look them up again with resolve() each time.
local current = nil          -- path of the focused button
-- Paths of buttons Enter was pressed on, oldest first; Backspace returns to them.
local back_stack = {}
local pending_click = nil    -- { button = path, menu = path, polls = n }
local click
local label_for

local function path_of(obj)
    return obj:GetFullName():match("^%S+%s+(.+)$")
end

local function resolve(path)
    if not path then return nil end
    local o = StaticFindObject(path)
    if o and o:IsValid() then return o end
    return nil
end

-- All visible, non-template text inside the button, in widget order.
local function label_of(path)
    local prefix = path .. "."
    local parts, seen = {}, {}
    local texts = FindAllOf("TextBlock")
    if not texts then return nil end
    for _, t in ipairs(texts) do
        if t:IsValid() then
            local tpath = path_of(t)
            if tpath and tpath:sub(1, #prefix) == prefix and t:IsVisible() then
                local ok, s = pcall(function() return t:GetText():ToString() end)
                if ok and s ~= "" and s:sub(1, 1) ~= "#" and not seen[s] then
                    seen[s] = true
                    parts[#parts + 1] = s
                end
            end
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Live widgets sit under /Engine/Transient; FindAllOf also returns blueprint
-- templates under /Game/..., which have no Slate widget behind them. Skip
-- those (an access violation inside UE4SS followed touching them, 2026-10-10).
local function live(obj)
    local path = path_of(obj)
    return path ~= nil and path:sub(1, 18) == "/Engine/Transient."
end
M.live = live

local function focused_button()
    local buttons = FindAllOf("CommonButtonBase")
    if not buttons then return nil end
    for _, b in ipairs(buttons) do
        if b:IsValid() and live(b) and (b:HasKeyboardFocus() or b:HasFocusedDescendants()) then
            return b
        end
    end
    return nil
end

-- Settings rows (STVUserSettingWidget): the value is not in their text when
-- it is a slider, so it is read and spoken separately.
local SETTING = nil
local function is_setting(b)
    SETTING = SETTING or StaticFindObject("/Script/STVoyager.STVUserSettingWidget")
    return SETTING ~= nil and SETTING:IsValid() and b:IsA(SETTING)
end

-- Section headings (Display, Graphics, DLSS Upsampling) are the same widget
-- with no arrow buttons; they have no value.
local function is_heading(b)
    local left = b.Button_Left
    return not (left and left:IsValid() and left:IsVisible())
end

-- Choice rows (Language, Screen Mode) show CarouselText; slider rows hide it,
-- and for them GetCarouselEntryFromValue returns the words "Invalid input".
local function setting_value(b)
    if is_heading(b) then return "section" end
    local v = b.CurrentValue
    local carousel = b.CarouselText
    if carousel and carousel:IsValid() and carousel:IsVisible() then
        return b:GetCarouselEntryFromValue(v):ToString()
    end
    return string.format("%d percent", math.floor(b:GetSliderPercentageFromValue(v) * 100 + 0.5))
end

local function with_value(label, b)
    if not is_setting(b) then return label end
    local value = setting_value(b)
    if label and label:find(value, 1, true) then return label end
    return label and (label .. ", " .. value) or value
end

-- Headings and blank spacer rows take focus too, so arrowing onto them said
-- "section" over and over. Skip to the next real setting in the direction of
-- travel; going down, the heading name is spoken with the setting it starts.
local last_dir = 1          -- 1 = Down, -1 = Up; set by the arrow key binds
local section_prefix = nil  -- heading to speak with the next label

local function title_of(b)
    local t = b.Title
    return (t and t:IsValid()) and t:GetText():ToString() or ""
end

local function skip_toward(list, start, dir)
    local heading = nil
    local i = start
    while true do
        local row = list:GetChildAt(i)
        if not (row and row:IsValid()) then return false end   -- ran off the end
        if is_setting(row) and not is_heading(row) then
            if dir > 0 and heading then section_prefix = heading .. " section" end
            row:SetFocus()
            return true
        end
        local t = title_of(row)
        if t ~= "" then heading = t end
        i = i + dir
    end
end

-- Returns true when it moved focus past a heading. Tries the direction of
-- travel first, then the other way (Enter lands on the top heading).
local function skip_heading(b)
    local list = b:GetParent()
    if not (list and list:IsValid()) then return false end
    local i = list:GetChildIndex(b)
    return skip_toward(list, i, last_dir) or skip_toward(list, i, -last_dir)
end

-- How many polls a pending click waits for a panel animation (100 ms each).
local MAX_WAIT_POLLS = 15

local crumb = require("crumb")

-- First launch only: the gamma screen after Performance Selection opens with
-- nothing focused, so nothing was spoken and Enter found no button (proven
-- 2026-10-11 with both CustomShow...SplashScreen flags set back to True in
-- GameUserSettings.ini). Focus its CONFIRM; Up and Down reach DARKER and
-- BRIGHTER from there.
local function focus_first_run_screen()
    for _, w in ipairs(FindAllOf("WBP_GammaCorrection_C") or {}) do
        if w:IsValid() and live(w) and w:IsInViewport() then
            local confirm = w.CloseButton
            if confirm and confirm:IsValid() then
                confirm:SetFocus()
                return confirm
            end
        end
    end
    return nil
end

-- Up and Down move through every screen, whatever its layout (Casey,
-- 2026-10-11: a screen reader user does not know whether things sit side
-- by side or one above another). The game only moves focus along its own
-- layout, so on a row (the away team slots) Up and Down did nothing, or
-- jumped to whatever lay below the row: Down on slot 1 went to Start
-- Mission and skipped slot 2 (2026-10-11). Moving focus from the mod after
-- the key raced the game's own move (items skipped, then a quarter-second
-- stall while focus was pulled back). Instead, when focus enters a window
-- that has a row, the mod gives the row's buttons and their neighbors
-- explicit Up and Down navigation rules in the window's widget order, so
-- the game itself moves to the right button. Other lists keep the game's
-- own navigation. Grids keep their own keys (ship view, System Map).
local NAV_UP, NAV_DOWN = 2, 3     -- EUINavigation
local wired = {}                  -- window path -> signature of its buttons
local BUTTON_CLASS, USER_WIDGET, PANEL = nil, nil, nil

local function buttons_in(w, out, depth)
    if depth > 40 or not (w and w:IsValid()) then return end
    if not require("screen").shown(w) then return end
    if w:IsA(BUTTON_CLASS) then
        if w:GetIsEnabled() then out[#out + 1] = w end
        return
    end
    if w:IsA(USER_WIDGET) then
        local tree = w.WidgetTree
        local root = tree and tree:IsValid() and tree.RootWidget
        if root and root:IsValid() then buttons_in(root, out, depth + 1) end
    elseif w:IsA(PANEL) then
        for i = 0, w:GetChildrenCount() - 1 do buttons_in(w:GetChildAt(i), out, depth + 1) end
    end
end

-- The widget above w, crossing from a UserWidget's tree to the UserWidget.
local function up_one(w)
    local parent = w:GetParent()
    if parent and parent:IsValid() then return parent end
    local tree = w:GetOuter()
    local owner = tree and tree:IsValid() and tree:GetOuter()
    if owner and owner:IsValid() and owner:IsA(USER_WIDGET) then return owner end
    return nil
end

-- Class name of the nearest panel that holds both a and b, or nil.
local function shared_panel(a, b)
    local above = {}
    local node, hops = up_one(a), 0
    while node and hops < 64 do
        above[path_of(node)] = node
        node, hops = up_one(node), hops + 1
    end
    node, hops = up_one(b), 0
    while node and hops < 64 do
        local hit = above[path_of(node)]
        if hit then return hit:GetClass():GetFName():ToString() end
        node, hops = up_one(node), hops + 1
    end
    return nil
end

local ROWS = { HorizontalBox = true, UniformGridPanel = true, WrapBox = true }

-- A window the mod reads that opens with nothing focused left Enter with
-- nothing to press: the Construction Report (2026-10-11), after the Gamma
-- screen and the away mission did the same. The game would not put
-- keyboard focus on the report's buttons even when asked (SetFocus and
-- SetKeyboardFocus both left HasKeyboardFocus false), so the mod keeps its
-- own current button for such a window: Up and Down move between its
-- buttons, Home and End go to the ends, Enter presses the current one. It
-- starts on Close, Confirm or Continue when there is one, else the first,
-- and is read once when the window opens. Tutorials close on Enter by
-- themselves and are left alone.
local PREFERRED = { "CloseButton", "ConfirmButton", "ContinueButton", "AcceptButton" }
local virtual = nil   -- { window = path, buttons = { paths }, index = n }

local function window_buttons(wpath)
    BUTTON_CLASS = BUTTON_CLASS or StaticFindObject("/Script/CommonUI.CommonButtonBase")
    USER_WIDGET = USER_WIDGET or StaticFindObject("/Script/UMG.UserWidget")
    PANEL = PANEL or StaticFindObject("/Script/UMG.PanelWidget")
    local w = resolve(wpath)
    local list = {}
    if w then buttons_in(w, list, 0) end
    -- Tab buttons switch a window's pages (Left and Right do that); in this
    -- list a room's "Management" tab read like a button that did nothing
    -- (2026-10-11).
    -- Also left out: invisible back buttons and buttons with no label at all
    -- (the Overview's six warp core upgrade buttons only display levels and
    -- were heard as a row of unlabeled buttons, 2026-10-11).
    local paths = {}
    for _, b in ipairs(list) do
        local p = path_of(b)
        local name = p:match("([^%.]+)$")
        local skip = name:match("Tab_?Button") or name:find("InvisBack", 1, true)
        if not skip then
            local ok, label = pcall(label_for, b, p)
            if ok and label and label ~= "" then paths[#paths + 1] = p end
        end
    end
    return paths
end

local function say_virtual()
    local b = virtual and resolve(virtual.buttons[virtual.index])
    if not b then return end
    local label = label_for(b, virtual.buttons[virtual.index]) or "Button"
    label = string.format("%s, %d of %d", label:gsub("%.$", ""), virtual.index, #virtual.buttons)
    print("[VoyagerAccess] window button: " .. label .. "\n")
    speech.say(label, false)
end

-- Called each poll when no button has real focus.
local track_wait = 0

local function track_unfocused_window()
    -- A dialogue takes Enter (continue) and focus: after Life Support came
    -- back on, its message took focus from the room and this list took
    -- Enter from the message (2026-10-11).
    if require("dialogue").active() then
        virtual = nil
        return
    end
    -- Every third poll (300 ms): finding the open windows scans many classes.
    track_wait = track_wait - 1
    if track_wait > 0 then return end
    track_wait = 3
    if virtual then
        local w = resolve(virtual.window)
        if w and require("screen").shown(w) then return end
        virtual = nil
    end
    for _, wpath in ipairs(require("popups").open_windows()) do
        if not wpath:find("Tutorial", 1, true) then
            local buttons = window_buttons(wpath)
            if #buttons > 0 then
                local index = 1
                for _, want in ipairs(PREFERRED) do
                    local found = nil
                    for i, bp in ipairs(buttons) do
                        if not found and bp:match("([^%.]+)$") == want then found = i end
                    end
                    if found then index = found break end
                end
                virtual = { window = wpath, buttons = buttons, index = index }
                say_virtual()
                return
            end
        end
    end
end

function M.virtual_active()
    if virtual and require("dialogue").active() then virtual = nil end
    return virtual ~= nil
end

function M.virtual_step(dir)
    if not virtual then return end
    local i = virtual.index + dir
    if virtual.buttons[i] then virtual.index = i end
    say_virtual()
end

function M.virtual_edge(last)
    if not virtual then return end
    virtual.index = last and #virtual.buttons or 1
    say_virtual()
end

function M.virtual_enter()
    local b = virtual and resolve(virtual.buttons[virtual.index])
    if not b then return end
    print("[VoyagerAccess] enter: window button " .. virtual.buttons[virtual.index] .. "\n")
    click(b)
end

local function wire_rows(path)
    BUTTON_CLASS = BUTTON_CLASS or StaticFindObject("/Script/CommonUI.CommonButtonBase")
    USER_WIDGET = USER_WIDGET or StaticFindObject("/Script/UMG.UserWidget")
    PANEL = PANEL or StaticFindObject("/Script/UMG.PanelWidget")
    -- The top of the button's real parent chain, not of its name: the away
    -- team hero buttons are named as top-level widgets but sit in a panel
    -- inside the loadout ("1 of 1" in the log, 2026-10-11).
    local root = resolve(path)
    if not root then return end
    for _ = 1, 64 do
        local up = up_one(root)
        if not up then break end
        root = up
    end
    local list = {}
    buttons_in(root, list, 0)
    local names = {}
    for i, b in ipairs(list) do names[i] = path_of(b) end
    local key, sig = path_of(root), table.concat(names, "|")
    if wired[key] == sig then return end
    wired[key] = sig
    -- A button is in a row when the nearest panel it shares with a
    -- neighbor lays them side by side. A grid with several rows (the full
    -- game may have more heroes) is still walked in widget order.
    local in_row = {}
    for i = 1, #list - 1 do
        if ROWS[shared_panel(list[i], list[i + 1])] then
            in_row[i], in_row[i + 1] = true, true
        end
    end
    local n = 0
    for i = 1, #list - 1 do
        if in_row[i] or in_row[i + 1] then
            list[i]:SetNavigationRuleExplicit(NAV_DOWN, list[i + 1])
            list[i + 1]:SetNavigationRuleExplicit(NAV_UP, list[i])
            n = n + 1
        end
    end
    if n > 0 then
        print(string.format("[VoyagerAccess] rows wired: %d links among %d buttons in %s\n",
            n, #list, key:match("([^%.]+)$")))
    end
end

-- The spoken label for a focused button.
label_for = function(b, path)
    local label
    if b:GetClass():GetFName():ToString() == "WBP_POISelectableOption_C" then
        label = require("events").option_label(b)
    elseif require("warpcore").handles(path) then
        label = require("warpcore").label(path)
    elseif require("awaymission").is_slot(path) then
        label = require("awaymission").slot_label(path) or with_value(label_of(path), b)
    elseif require("awaymission").is_hero_button(path) then
        label = require("awaymission").hero_label(path) or with_value(label_of(path), b)
    elseif require("rooms").is_hero_button(path) then
        label = require("rooms").hero_label(path) or with_value(label_of(path), b)
    elseif require("rooms").is_module_button(path) then
        label = require("rooms").button_label(path, with_value(label_of(path), b) or "Button")
    elseif require("dialogue").is_choice(path) then
        label = require("dialogue").choice_label(path) or with_value(label_of(path), b)
    else
        label = with_value(label_of(path), b)
    end
    return label
end

local function poll()
    crumb.at("focus: pending click")
    if pending_click then
        local p = pending_click
        p.polls = p.polls + 1
        local menu = resolve(p.menu)
        local switcher = menu and menu.ContentPanel
        local animating = switcher and switcher:IsValid() and switcher:IsTransitionPlaying()
        if not animating or p.polls >= MAX_WAIT_POLLS then
            pending_click = nil
            local button = resolve(p.button)
            if button then click(button) end
        end
    end
    crumb.at("focus: scan buttons")
    local b = focused_button()
    if not b then b = focus_first_run_screen() end
    if b then virtual = nil elseif not current then track_unfocused_window() end
    local path = b and path_of(b) or nil
    if path == current then return end
    crumb.at("focus: changed to " .. tostring(path))
    current = path
    if path then
        local ok, err = pcall(wire_rows, path)
        if not ok then print("[VoyagerAccess] rows error: " .. tostring(err) .. "\n") end
    end
    if not path then return end
    -- Arriving back at a button Enter was pressed on closes everything opened after it.
    for i = #back_stack, 1, -1 do
        if back_stack[i] == path then
            for j = #back_stack, i, -1 do back_stack[j] = nil end
            break
        end
    end
    if is_setting(b) and is_heading(b) and skip_heading(b) then return end
    crumb.at("focus: label of " .. path)
    local label = label_for(b, path)
    if section_prefix then
        label = label and (section_prefix .. ", " .. label) or section_prefix
        section_prefix = nil
    end
    print(string.format("[VoyagerAccess] focus: %s | %s\n", tostring(label), path))
    if label then speech.say(label, true) end
end

-- The game binds no keyboard key to Accept (only Escape, to Cancel), so
-- Enter runs CommonUI's own press/release/click on the focused button.
-- Proven on Exit, profiles (focus moves to the save panel) and New Game
-- (2026-10-10).
--
-- Main-menu panels open on mouse hover or gamepad focus, not keyboard focus
-- (proven 2026-10-10), and the click handlers only move focus into an
-- already-open panel. So Enter opens the panel first. Values are the
-- ESTVMainMenuContentPanelItems index; 1 = settings and 2 = save panel are
-- proven, 0 is untested (a crash followed calling it).
local SETTINGS_PANEL, SAVE_PANEL = 1, 2

-- A profile's hover points the save panel at that profile and fills it in.
-- The native Setup is not callable from Lua, but setting ProfileIndex and
-- LeftNavigationTarget, then OnSaveSlotsChanged (which runs UpdateButtons),
-- fills it correctly (proven 2026-10-10: Caretaker, Continue Game, Restart
-- Sector, Delete). Without this the panel shows the last profile, or
-- placeholder text.
local function point_save_panel_at(menu, b)
    local w = menu.SectorSaveWindow
    if not (w and w:IsValid()) then return false end
    w.ProfileIndex = b.ProfileIndex
    w.LeftNavigationTarget = b
    menu:ShowContentPanel(SAVE_PANEL)
    local manager
    for _, m in ipairs(FindAllOf("STVSaveGameManager") or {}) do
        if live(m) then manager = m end
    end
    w:OnSaveSlotsChanged(manager)
    return true
end

-- Returns the menu when it opened a panel, nil otherwise.
local function open_panel_for(b)
    local outer = b:GetOuter()                 -- the menu's WidgetTree
    local menu = outer and outer:GetOuter()
    if not (menu and menu:IsValid() and menu:GetClass():GetFName():ToString() == "WBP_MainMenu_C") then
        return nil
    end
    if b:GetFName():ToString() == "SettingsButton" then
        menu:ShowContentPanel(SETTINGS_PANEL)
        return menu
    end
    if b:GetClass():GetFName():ToString() == "WBP_Button_SaveProfile_C" then
        return point_save_panel_at(menu, b) and menu or nil
    end
    return nil
end

function click(b)
    b:HandleButtonPressed()
    b:HandleButtonReleased()
    b:HandleButtonClicked()
end

local function activate()
    crumb.at("key: enter on " .. tostring(current))
    if require("popups").close_tutorial() then return end
    -- In a dialogue, Enter continues unless an on-screen dialogue button (a
    -- choice, a story card's Continue) has focus. The story card's Continue
    -- kept focus after the card closed, so Enter clicked a hidden button and
    -- the dialogue never moved on (2026-10-10).
    local dialogue = require("dialogue")
    -- A dialogue choice is its own widget, outside the dialogue window, so
    -- the check below took Enter on a choice for "continue" (2026-10-11).
    -- Click the choice's main button (RightButton, with the wording); the
    -- focused LeftButton is the number tag, a hold-to-pick for gamepads.
    -- Only while the choice is on screen: after picking one, focus stayed
    -- on the hidden choice and Enter kept picking it (2026-10-11).
    local choice = dialogue.is_choice(current) and resolve(current)
    if choice and require("screen").shown(choice) then
        local cpath = current:match("^(.-WBP_Dialogue_Choice_Sector_C_%d+)")
        local c = cpath and resolve(cpath)
        local target = c and c.RightButton
        if not (target and target:IsValid()) then target = resolve(current) end
        if target then
            print("[VoyagerAccess] enter: choice " .. tostring(current) .. "\n")
            click(target)
            return
        end
    end
    local focused = resolve(current)
    local on_screen = focused ~= nil and require("screen").shown(focused)
    if dialogue.active() and not (on_screen and dialogue.contains(current)) then
        dialogue.continue()
        return
    end
    local b = resolve(current)
    if not b then
        print("[VoyagerAccess] enter: no focused button\n")
        return
    end
    print("[VoyagerAccess] enter: clicking " .. tostring(current) .. "\n")
    -- Enter on a settings row opens nothing, so it is not a place to go back to.
    if not is_setting(b) and back_stack[#back_stack] ~= current then
        back_stack[#back_stack + 1] = current
    end
    -- A settings category whose page is already showing ignores the click
    -- (selection does not change, so the game does nothing), so focus the
    -- page's own desired target instead (proven 2026-10-10 on Graphics).
    local outer = b:GetOuter()
    local window = outer and outer:GetOuter()
    if b:GetSelected() and window and window:IsValid()
        and window:GetClass():GetFName():ToString() == "WBP_SettingsWindow_C" then
        local page = window.ContentPanel:GetActiveWidget()
        local target = page and page:IsValid() and page:GetDesiredFocusTarget()
        if target and target:IsValid() then
            target:SetFocus()
            return
        end
    end
    local menu = open_panel_for(b)
    if menu then
        -- The click moves focus into the panel only once the panel is up;
        -- in the same tick it did nothing, and one poll later it still
        -- failed about half the time (Casey had to press Enter twice), so
        -- poll() waits for the panel animation to finish.
        pending_click = { button = current, menu = path_of(menu), polls = 0 }
    else
        local before = label_for(b, current)
        local path = current
        click(b)
        -- The power button's text changed later than 400 ms (Switch Off on
        -- Life Support, 2026-10-11), so check every 300 ms for 2.4 s.
        local function check(tries)
            local done = true
            pcall(function()
                local now = resolve(path)
                if not (now and require("screen").shown(now)) then return end
                local after = label_for(now, path)
                if after and after ~= before then
                    print("[VoyagerAccess] changed: " .. after .. "\n")
                    speech.say(after, true)
                else
                    done = false
                end
            end)
            if not done and tries > 1 then
                ExecuteInGameThreadWithDelay(300, function() check(tries - 1) end)
            end
        end
        ExecuteInGameThreadWithDelay(300, function() check(8) end)
    end
end

-- Backspace: return focus to the button Enter was last pressed on. The game
-- has no keyboard Back of its own (Escape does not close the save panel).
local function go_back()
    crumb.at("key: backspace")
    while #back_stack > 0 do
        local path = table.remove(back_stack)
        local b = path ~= current and resolve(path) or nil
        if b and b:IsVisible() then
            print("[VoyagerAccess] back: " .. path .. "\n")
            b:SetFocus()
            return
        end
    end
    speech.say("Nothing to go back to", true)
end

-- Left/Right on a settings row: the game only wires these to the mouse
-- (the row's arrow buttons) and gamepad, so the mod calls the game's own
-- ChangeValueFromInput and speaks the new value.
local function adjust(left)
    crumb.at("key: left/right")
    local b = resolve(current)
    if not (b and is_setting(b)) or is_heading(b) then return end
    b:ChangeValueFromInput(left)
    local value = setting_value(b)
    print("[VoyagerAccess] adjust: " .. value .. "\n")
    speech.say(value, true)
end

M.path_of = path_of
M.label_of = label_of

-- Home and End in a game menu: focus the first or last on-screen button in
-- the focused button's own list (Casey: every list goes to its top and
-- bottom with Home and End, 2026-10-10). Settings headings are skipped.
local BUTTON = nil
local function edge(last)
    crumb.at("key: home/end")
    local b = resolve(current)
    if not b then return end
    local list = b:GetParent()
    if not (list and list:IsValid()) then return end
    BUTTON = BUTTON or StaticFindObject("/Script/CommonUI.CommonButtonBase")
    local n = list:GetChildrenCount()
    local from, to, step = 0, n - 1, 1
    if last then from, to, step = n - 1, 0, -1 end
    for i = from, to, step do
        local row = list:GetChildAt(i)
        if row and row:IsValid() and row:IsA(BUTTON) and require("screen").shown(row)
            and not (is_setting(row) and is_heading(row)) then
            row:SetFocus()
            return
        end
    end
end

-- For L (where am I): the focused button as the arrows read it, or nil.
function M.current_label()
    local b = resolve(current)
    if not (b and require("screen").shown(b)) then return nil end
    local ok, label = pcall(label_for, b, current)
    return ok and label or nil
end

-- "settings" or "menu" when an on-screen button has focus, else nil.
function M.context()
    local b = resolve(current)
    if not (b and require("screen").shown(b)) then return nil end
    return is_setting(b) and "settings" or "menu"
end

function M.install()
    local keys = require("keys")
    local ship = require("ship")
    -- In the ship view the arrows and Enter walk the rooms, unless a
    -- dialogue or an on-screen menu button has focus.
    local function ship_mode()
        if require("dialogue").active() then return false end
        local b = resolve(current)
        if b and require("screen").shown(b) then return false end
        return ship.active()
    end
    local system = require("system")
    local function map_mode()
        if require("dialogue").active() then return false end
        local b = resolve(current)
        if b and require("screen").shown(b) then return false end
        return system.active()
    end
    -- Away mission choices: the game has no keyboard path, so the mod
    -- walks them (awaymission.lua).
    local away = require("awaymission")
    keys.on("enter", function()
        if require("popups").close_tutorial() then return end
        if require("resources").list_open() then return require("resources").close() end
        if require("view").nav_open() then return require("view").nav_enter() end
        if away.mission_active() then return away.mission_enter() end
        if M.virtual_active() then return M.virtual_enter() end
        if ship_mode() then return ship.open() end
        if map_mode() then return system.enter() end
        activate()
    end)
    keys.on("backspace", function()
        if require("resources").close() then return end
        if require("view").nav_close() then return end
        if map_mode() and system.menu_close() then return end
        go_back()
    end)
    -- Lists move with Up and Down everywhere (Casey, 2026-10-10); Left and
    -- Right change values. Page Up and Down change deck in the ship view.
    keys.on("up", function()
        if require("resources").list_open() then require("resources").step(-1)
        elseif require("view").nav_open() then require("view").nav_step(-1)
        elseif away.mission_active() then away.mission_step(-1)
        elseif M.virtual_active() then M.virtual_step(-1)
        elseif require("warpcore").handles(current) then require("warpcore").move(current, 1)
        elseif ship_mode() then ship.deck(-1)
        elseif map_mode() then if system.menu_open() then system.menu_step(-1) else system.step(-1) end
        else last_dir = -1 end
    end)
    keys.on("down", function()
        if require("resources").list_open() then require("resources").step(1)
        elseif require("view").nav_open() then require("view").nav_step(1)
        elseif away.mission_active() then away.mission_step(1)
        elseif M.virtual_active() then M.virtual_step(1)
        elseif require("warpcore").handles(current) then require("warpcore").move(current, -1)
        elseif ship_mode() then ship.deck(1)
        elseif map_mode() then if system.menu_open() then system.menu_step(1) else system.step(1) end
        else last_dir = 1 end
    end)
    local rooms = require("rooms")
    keys.on("left", function()
        if require("view").overview_tab(-1) then return end
        if rooms.window_open() then rooms.switch_tab(-1)
        elseif ship_mode() then ship.step(-1) elseif not map_mode() then adjust(true) end
    end)
    keys.on("right", function()
        if require("view").overview_tab(1) then return end
        if rooms.window_open() then rooms.switch_tab(1)
        elseif ship_mode() then ship.step(1) elseif not map_mode() then adjust(false) end
    end)
    keys.on("pageup", function() if ship_mode() then ship.deck(-1) end end)
    keys.on("pagedown", function() if ship_mode() then ship.deck(1) end end)
    local function home_end(last)
        if require("resources").list_open() then return require("resources").edge(last) end
        if require("view").nav_open() then return require("view").nav_edge(last) end
        if away.mission_active() then return away.mission_edge(last) end
        if M.virtual_active() then return M.virtual_edge(last) end
        if ship_mode() then return ship.edge(last) end
        if map_mode() then
            if system.menu_open() then return system.menu_edge(last) end
            return system.edge(last)
        end
        edge(last)
    end
    keys.on("home", function() home_end(false) end)
    keys.on("end", function() home_end(true) end)
    -- On the game thread directly; LoopAsync plus ExecuteInGameThread is a
    -- suspect in an idle crash inside UE4SS (2026-10-10 20:28, not proven).
    LoopInGameThreadWithDelay(INTERVAL_MS, function()
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] focus error: " .. tostring(err) .. "\n") end
    end)
    print("[VoyagerAccess] focus polling installed\n")
end

return M
