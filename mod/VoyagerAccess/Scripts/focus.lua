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
local ticks, focus_tick = 0, -100   -- focus polls so far, and the poll choices appeared
local choice_seen_at = -100         -- os.clock() when the focused dialogue choice was last on screen
local arrow_tick = -100              -- the poll the game was last given Up or Down
local go_in_until = -100             -- polls until which a crossing in the main menu is allowed (Enter, Right, Left, Backspace, Escape)
-- Paths of buttons Enter was pressed on, oldest first; Backspace returns to them.
local back_stack = {}
local pending_click = nil    -- { button = path, menu = path, polls = n }
local click
local label_for
local restore_focus

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
-- Texts in a collapsed box count as hidden: the full game's main menu buttons
-- keep a "0LY" there, and it was spoken after every item (2026-10-14).
local function label_of(path)
    local prefix = path .. "."
    local parts, seen = {}, {}
    local texts = FindAllOf("TextBlock")
    if not texts then return nil end
    for _, t in ipairs(texts) do
        if t:IsValid() then
            local tpath = path_of(t)
            -- A DLC tile's entitlement badge ("Dx", "1, 2, 3, 4", 2026-10-14)
            -- says nothing in speech; its title follows.
            if tpath and tpath:sub(1, #prefix) == prefix and not tpath:find("%.Entitlement_TXT$")
                    and require("screen").shown(t) then
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
    -- The innermost one: the incoming call list sits inside the Incoming
    -- Calls button, both had focused descendants, and the outer, unlabeled
    -- one was taken, so the call was never read (2026-10-14).
    local best, best_len = nil, -1
    for _, b in ipairs(buttons) do
        if b:IsValid() and live(b) and (b:HasKeyboardFocus() or b:HasFocusedDescendants()) then
            local len = #path_of(b)
            if len > best_len then best, best_len = b, len end
        end
    end
    return best
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
    -- Clamped: Severity (Accessibility) starts at a stored 10 on a 0 to 1
    -- slider, drawn full, and was spoken as 1000 percent (2026-10-14).
    local pct = math.floor(b:GetSliderPercentageFromValue(v) * 100 + 0.5)
    return string.format("%d percent", math.max(0, math.min(100, pct)))
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
                -- After the game window loses the foreground the gamma
                -- window keeps keyboard focus itself and SetFocus does
                -- nothing; claiming CONFIRM anyway left the arrows silent
                -- (2026-10-14, VM, real alt-tab). Return nothing so the
                -- window button list takes over.
                if confirm:HasKeyboardFocus() or confirm:HasFocusedDescendants() then
                    return confirm
                end
                return nil
            end
        end
    end
    return nil
end

-- Radial menus (WBP_RadialMenu, a ship room's action ring: Clear debris on a
-- ruined room) open with nothing focused and the mod said nothing
-- (2026-10-14). Focus the first segment and give the segments Up and Down
-- in ring order; Enter clicks the focused one as usual.
local RADIAL_NAMES = { DestroyRuin = "Clear debris" }
local function focus_radial()
    local menu = nil
    for _, w in ipairs(FindAllOf("WBP_RadialMenu_C") or {}) do
        if w:IsValid() and live(w) and require("screen").shown(w) then menu = w end
    end
    if not menu then return nil end
    local list = {}
    for _, it in ipairs(M.ring_buttons(path_of(menu))) do list[#list + 1] = it.b end
    if #list == 0 then return nil end
    for i = 1, #list do
        pcall(function()
            if list[i - 1] then list[i]:SetNavigationRuleExplicit(2, list[i - 1]) else list[i]:SetNavigationRuleBase(2, 3) end
            if list[i + 1] then list[i]:SetNavigationRuleExplicit(3, list[i + 1]) else list[i]:SetNavigationRuleBase(3, 3) end
        end)
    end
    list[1]:SetFocus()
    if list[1]:HasKeyboardFocus() or list[1]:HasFocusedDescendants() then return list[1] end
    return nil
end

-- The ring's segments in their visual order, clockwise from the top
-- (RenderTransform.Angle 0, 60, 120...); path order was arbitrary.
local function ring_buttons(menu)
    local list = {}
    for _, o in ipairs(FindAllOf("WBP_RadialButton_C") or {}) do
        local p = o:IsValid() and path_of(o)
        if p and p:sub(1, #menu + 1) == menu .. "." and require("screen").shown(o) then
            local ok, a = pcall(function() return o.RenderTransform.Angle end)
            list[#list + 1] = { b = o, path = p, angle = (ok and type(a) == "number") and a or 0 }
        end
    end
    table.sort(list, function(x, y)
        if x.angle ~= y.angle then return x.angle < y.angle end
        return x.path < y.path
    end)
    return list
end

M.ring_buttons = ring_buttons

-- A segment's name from its command asset, for when its details cannot be
-- read. "OpenMenu_RoomCategory_BorgTechnology" was read "Open menu_room
-- category_borg technology" (2026-10-14): a category is named alone.
function M.radial_label(b)
    local ok, name = pcall(function() return b.Command:GetFName():ToString() end)
    if not ok or not name then return nil end
    local key = name:gsub("^DA_Command_", "")
    local function words(s)
        return (s:gsub("_", " "):gsub("(%l)(%u)", "%1 %2"):gsub("%s+", " "):lower():gsub("^%l", string.upper))
    end
    local category = key:match("^OpenMenu_RoomCategory_(.+)$") or key:match("^OpenMenu_(.+)$")
    key = key:gsub("^ConstructRoom_", "")
    local label = RADIAL_NAMES[key] or (category and words(category)) or words(key)
    local locked = false
    pcall(function() locked = require("screen").shown(b.LockImage) end)
    if locked then label = label .. ", locked" end
    return label
end

-- "n of m" for a segment.
local function ring_place(b)
    local menu = path_of(b):match("^(.-WBP_RadialMenu_C_%d+)%.")
    if not menu then return "" end
    local list = ring_buttons(menu)
    for i, it in ipairs(list) do
        if it.path == path_of(b) then return string.format("%d of %d", i, #list) end
    end
    return ""
end

-- What the ring's centre shows while a segment is hovered: a build menu's
-- WBP_RadialMenuCenter_BuildRoom has the room's name, a missing-resources
-- warning, its description, operation and construction costs. That only
-- appears on mouse hover (2026-10-14), so the mod hovers the focused one.
local function radial_details(menu)
    local by, order = {}, {}
    local center = nil
    -- Clear Debris shows what it gives back as "+16" in a DuraniumDisplay
    -- (WBP_RadialMenuCenter_ClearDebris, VM, 2026-10-15); every display's
    -- number is named AmountText, so the resource is the display's name.
    local gives, gave = {}, {}
    for _, cls in ipairs({ "TextBlock", "RichTextBlock", "CommonTextBlock", "CommonRichTextBlock" }) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            local tp = t:IsValid() and path_of(t)
            -- The centre is not inside the ring's path; any shown one counts.
            if tp and tp:find("^/Engine/Transient%.") and tp:find("WBP_RadialMenuCenter_", 1, true)
                and require("screen").shown(t) then
                local name = tp:match("([^%.]+)$")
                center = center or tp:match("^(.-WBP_RadialMenuCenter_[%w_]-_C_%d+)%.")
                local ok, s = pcall(function() return t:GetText():ToString() end)
                -- The shared clean-up first: a Cargo Bay's description lists
                -- "<img id="Deuterium"/> +500 storage capacity" a line each,
                -- read as "+500 storage capacity +500 storage capacity"
                -- (VM, 2026-10-15).
                if ok and s then s = require("text").prep(s) end
                s = (ok and s) and s:gsub("<[^>]*>", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "") or ""
                local res = tp:match("%.(%w+)Display%.WidgetTree_%d+%.AmountText$")
                if res then
                    if s:match("%d") and not s:find("#", 1, true) and not gave[res] then
                        gave[res] = true
                        gives[#gives + 1] = (s:gsub("^%+", "")) .. " " .. (res:gsub("(%l)(%u)", "%1 %2")):lower()
                    end
                elseif s ~= "" and not by[name] then by[name] = s; order[#order + 1] = name end
            end
        end
    end
    if not by.CenterText then
        local parts = {}
        for _, n in ipairs(order) do parts[#parts + 1] = by[n] end
        return #parts > 0 and table.concat(parts, ". ") or nil
    end
    local parts = { by.CenterText }
    if by.ErrorText then parts[#parts + 1] = by.ErrorText end
    if by.RoomDescriptionText then parts[#parts + 1] = by.RoomDescriptionText end
    if by.DescriptionText then parts[#parts + 1] = by.DescriptionText end
    if #gives > 0 then parts[#parts + 1] = "Gives " .. table.concat(gives, ", ") end
    local op = {}
    if by.EnergyValue then op[#op + 1] = "energy " .. by.EnergyValue end
    if by.CrewValue then op[#op + 1] = "crew " .. by.CrewValue end
    if #op > 0 then parts[#parts + 1] = (by.OperationText or "Operation") .. ": " .. table.concat(op, ", ") end
    local build = {}
    local okc, costs = pcall(function() return center and require("rooms").costs_under(center) or "" end)
    if okc and costs ~= "" then build[#build + 1] = costs end
    if by.WorkteamsValue then build[#build + 1] = by.WorkteamsValue .. (by.WorkteamsValue == "1" and " work team" or " work teams") end
    if by.CyclesValue then build[#build + 1] = by.CyclesValue .. (by.CyclesValue == "1" and " cycle" or " cycles") end
    if #build > 0 then parts[#parts + 1] = (by.BuildText or "Construction") .. ": " .. table.concat(build, ", ") end
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    return table.concat(parts, ". ")
end

local radial_said = {}   -- segment path -> what was said, for L and R

-- Focus reached a segment: hover it with the mouse (through the helper),
-- then say the centre's details and its place in the ring; with no
-- details (no helper, or a centre without them), the command's name.
function M.radial_focus(b, path)
    local menu = path:match("^(.-WBP_RadialMenu_C_%d+)%.")
    pcall(function()
        local pos = b.Slot:GetPosition()
        local r = math.max(math.sqrt(pos.X * pos.X + pos.Y * pos.Y), 1)
        speech.ring_mouse(pos.X / r, pos.Y / r)
    end)
    ExecuteInGameThreadWithDelay(450, function()
        pcall(function()
            if current ~= path then return end
            local nb = resolve(path)
            if not nb then return end
            local text = menu and radial_details(menu) or nil
            -- A room to build: when the hover did not reach this room (no
            -- mouse, or a game that ignores it), read it from the game's data.
            local okr, ring = pcall(require("construction").ring_text, nb)
            if okr and ring and not (text and ring.check ~= "" and text:find(ring.check, 1, true)) then
                print("[VoyagerAccess] radial: centre not for this room, read from data\n")
                text = ring.text
            end
            if not text or text == "" then text = M.radial_label(nb) or "Button" end
            -- A room to build: its width and whether it fits at the selected
            -- space (construction.lua).
            local okf, fit = pcall(require("construction").fit_text, nb)
            if okf and fit then text = text:gsub("%.%s*$", "") .. ". " .. fit end
            local place = ring_place(nb)
            if place ~= "" then text = text .. ". " .. place end
            radial_said[path] = text
            print("[VoyagerAccess] radial: " .. text .. "\n")
            speech.say(text, true)
        end)
    end)
end

function M.radial_said(path)
    return radial_said[path]
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
-- AcceptButton_1: the Q Trials warning's ACCEPT (ABORT is CloseButton_1).
local PREFERRED = { "CloseButton", "ConfirmButton", "ContinueButton", "AcceptButton", "AcceptButton_1" }
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
    -- A combat order wheel's Back came first ("Back, 1 of 6", 2026-10-14):
    -- it goes last.
    for i, p in ipairs(paths) do
        if p:find("%.BackButton$") and i < #paths then
            table.remove(paths, i)
            paths[#paths + 1] = p
            break
        end
    end
    return paths
end

local function say_virtual()
    local b = virtual and resolve(virtual.buttons[virtual.index])
    if not b then return end
    -- No label yet: "Button, 1 of 1" was said as a Mess Hall opened, before
    -- focus moved to its real first button (VM, 2026-10-15).
    local label = label_for(b, virtual.buttons[virtual.index])
    if not label or label == "" then return end
    if M.wheel_locked(b) then label = label:gsub("%.$", "") .. ", not available now" end
    -- An event option already says its place ("1 of 2, 2 locked, 1 of 2",
    -- VM, 2026-10-14).
    if not label:gsub("health %d+ of %d+", ""):find("%d+ of %d+") then
        label = string.format("%s, %d of %d", label:gsub("%.$", ""), virtual.index, #virtual.buttons)
    end
    print("[VoyagerAccess] window button: " .. label .. "\n")
    speech.say(label, false)
end

-- Called each poll when no button has real focus.
local track_wait = 0

-- After the game window loses and regains the foreground, a menu can be
-- left with nothing focused, and the arrows do nothing (main menu,
-- 2026-10-11). Put focus back on the last button that had it, if it is
-- still on screen. Not in the ship view or System Map, where having no
-- focus is normal, and not during dialogue. Tried every second at most.
local last_real = nil
local restore_wait = 0

-- A mod list (What's new, status) open over a focused menu: the game also
-- gets Up and Down, so the menu moved with the list and both talked
-- (2026-10-11). Opening a list parks the game's focus on the viewport;
-- closing it lets restore_focus put it back.
local function mod_list_open()
    return require("whatsnew").open() or require("hotkeys").open() or require("resources").list_open() or require("credits").open()
        or require("ship").list_open() or require("techtree").open()
end

function M.park_focus()
    pcall(function()
        StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):SetFocusToGameViewport()
    end)
end

restore_focus = function()
    if not last_real or mod_list_open() then return false end
    restore_wait = restore_wait - 1
    if restore_wait > 0 then return false end
    restore_wait = 10
    local ctx = require("help").context()
    if ctx == "ship" or ctx == "system" or ctx == "dialogue" or ctx == "cutscene" or ctx == "story" then return false end
    local b = resolve(last_real)
    if not (b and require("screen").shown(b)) then
        -- Hidden under the player: a battle's third hero slot hid once no
        -- hero was left for it, focus was on it, and the arrows went silent
        -- (Q Trials ambush, VM, 2026-10-15). The nearest shown button in the
        -- same window takes focus instead.
        local near, prefix = nil, last_real
        for _ = 1, 4 do
            prefix = prefix:match("^(.+)%.[^%.]+$")
            if not prefix or not prefix:find("WidgetTree_", 1, true) then break end
            for _, o in ipairs(FindAllOf("CommonButtonBase") or {}) do
                local op = o:IsValid() and live(o) and path_of(o)
                if op and op:sub(1, #prefix + 1) == prefix .. "." and require("screen").shown(o) then near = o break end
            end
            if near then break end
        end
        last_real = nil
        if not near then return false end
        print("[VoyagerAccess] focus: hidden, moving to " .. path_of(near):match("([^%.]+)$") .. "\n")
        near:SetFocus()
        return true
    end
    -- Not behind an open window: the Q Trials warning (focusless buttons)
    -- had focus put back on NEW Q TRIAL under it, where Enter would press
    -- it again (2026-10-14). The window's button list takes over instead.
    for _, wp in ipairs(require("popups").open_windows()) do
        if last_real:sub(1, #wp + 1) ~= wp .. "." and #window_buttons(wp) > 0 then return false end
    end
    print("[VoyagerAccess] focus: restoring " .. last_real:match("([^%.]+)$") .. "\n")
    b:SetFocus()
    return true
end

local PAUSE_CONFIRM = "WBP_PauseMenu_Confirms_C"
-- Confirmations whose buttons never take focus. The main menu's Delete
-- Profile warning is its own class (GXCommonInfoWidget), and focus went
-- back to the menu behind it (VM, 2026-10-15).
local CONFIRMS = { PAUSE_CONFIRM, "WBP_DeleteProfileWarning_C" }
-- The save window's other warnings (Overwrite Savegame and the like).
for _, c in ipairs(require("popups").SAVE_WARNINGS) do CONFIRMS[#CONFIRMS + 1] = c end
for _, c in ipairs(require("popups").ROOM_WARNINGS) do CONFIRMS[#CONFIRMS + 1] = c end
local function is_confirm(p)
    for _, c in ipairs(CONFIRMS) do if p:find(c, 1, true) then return true end end
    return false
end
local function open_confirm()
    for _, c in ipairs(CONFIRMS) do
        for _, w in ipairs(FindAllOf(c) or {}) do
            if w:IsValid() and live(w) and require("screen").shown(w) then return w end
        end
    end
    return nil
end
local function pause_confirm_open()
    return open_confirm() ~= nil
end

-- Windows whose buttons never take keyboard focus: the pause menu's
-- confirmation, and the Q Trials warning (while its Warning page shows).
-- Returns the open one's path, or nil.
local function focusless_window()
    local cw = open_confirm()
    if cw then return path_of(cw) end
    for _, w in ipairs(FindAllOf("WBP_Sandbox_Setup_C") or {}) do
        if w:IsValid() and live(w) and require("screen").shown(w) then
            local warn = w.Warning
            if warn and warn:IsValid() and require("screen").shown(warn) then return path_of(w) end
        end
    end
    return nil
end
M.focusless_window = focusless_window

local function track_unfocused_window()
    -- A dialogue takes Enter (continue) and focus: after Life Support came
    -- back on, its message took focus from the room and this list took
    -- Enter from the message (2026-10-11).
    -- Except the pause menu's confirmation ("Exit to Main Menu"), which sits
    -- over the dialogue and whose buttons never take focus (2026-10-14).
    if require("dialogue").active() and not pause_confirm_open() then
        virtual = nil
        return
    end
    -- Every third poll (300 ms): finding the open windows scans many classes.
    track_wait = track_wait - 1
    if track_wait > 0 then return end
    track_wait = 3
    -- A confirmation inside a window goes first, alone: the away team's
    -- start warning's Return and Continue were mixed into a list of ten
    -- with the slots and heroes behind it (2026-10-14).
    local windows = require("popups").open_windows()
    local modal = nil
    for _, p in ipairs(windows) do
        if p:find("WBP_AM_ConfirmStart_C", 1, true) or p:find("FewerHeroesConfirmWidget", 1, true)
            or is_confirm(p) then
            -- Only one on screen: the battle setup's start warning has a
            -- hidden twin, and taking it left the real one with no list, so
            -- the keys went to the setup behind it (VM, 2026-10-16).
            local mw = resolve(p)
            if mw and require("screen").shown(mw) then modal = p end
        end
    end
    if modal then windows = { modal } end
    if virtual then
        local w = resolve(virtual.window)
        -- A combat order wheel swaps its buttons in place (Offensive
        -- Actions opened the enemy's subsystems, and the list kept the old
        -- buttons, 2026-10-14): rebuild when a listed button has gone.
        local all_there = true
        for _, bp in ipairs(virtual.buttons) do
            local vb = resolve(bp)
            if not (vb and require("screen").shown(vb)) then all_there = false break end
        end
        if all_there and w and require("screen").shown(w) and (not modal or virtual.window == modal) then
            -- Buttons that appear later join the list where the window has
            -- them, and the place in it is kept: a work team added in the
            -- Engineering Office never got its row (VM, 2026-10-16).
            -- Checked about once a second.
            virtual.recheck = (virtual.recheck or 0) + 1
            if virtual.recheck >= 3 then
                virtual.recheck = 0
                local okf, fresh = pcall(window_buttons, virtual.window)
                if okf and fresh and #fresh > 0 then
                    local known = {}
                    for _, bp in ipairs(virtual.buttons) do known[bp] = true end
                    local added = false
                    for _, bp in ipairs(fresh) do if not known[bp] then added = true end end
                    if added then
                        local at = virtual.buttons[virtual.index]
                        -- Buttons from other windows in the list stay at the end.
                        local in_fresh = {}
                        for _, bp in ipairs(fresh) do in_fresh[bp] = true end
                        for _, bp in ipairs(virtual.buttons) do
                            if not in_fresh[bp] then fresh[#fresh + 1] = bp end
                        end
                        virtual.buttons = fresh
                        for i, bp in ipairs(fresh) do if bp == at then virtual.index = i end end
                        print("[VoyagerAccess] window list: " .. #fresh .. " buttons now\n")
                    end
                end
            end
            -- Its first button, once the window's message has been read.
            if virtual.unsaid and require("popups").was_announced(virtual.window) then
                virtual.unsaid = nil
                say_virtual()
            end
            return
        end
        virtual = nil
    end
    -- Windows the mod can give real focus to do not need the list.
    local okw, focused = pcall(function() return require("rooms").prepare_workteams() end)
    if okw and focused then return end
    -- The buttons of every open window together: the Research Report's
    -- rewards are a second window, and taking only the first window with
    -- buttons left Close Report and Enter Ship out of reach (2026-10-14).
    local buttons, first, seen = {}, nil, {}
    for _, wpath in ipairs(windows) do
        -- Nor the map's point details: their item rewards are buttons, read
        -- with the details already, and as a list they took the arrows from
        -- the map ("Kazon Tactical Intel, 1 of 1" after a scan, Backspace
        -- said "Nothing to go back to", Q Trials, VM, 2026-10-15).
        if not wpath:find("Tutorial", 1, true) and not wpath:find("POIDetailView", 1, true) then
            for _, bp in ipairs(window_buttons(wpath)) do
                if not seen[bp] then
                    seen[bp] = true
                    buttons[#buttons + 1] = bp
                    first = first or wpath
                end
            end
        end
    end
    if #buttons > 0 then
        local index = 1
        for _, want in ipairs(PREFERRED) do
            local found = nil
            for i, bp in ipairs(buttons) do
                if not found and bp:match("([^%.]+)$") == want then found = i end
            end
            if found then index = found break end
        end
        virtual = { window = first, buttons = buttons, index = index }
        -- The pause menu's confirmation and the Q Trials warning: their first
        -- button waits until popups.lua has read the message (it came first,
        -- "BACK, 1 of 2" before "Exit to Main Menu", 2026-10-14), and is said
        -- by the check above once it has.
        -- Every window now: a side mission offer said "Acknowledged, 1 of 1"
        -- before its message (Q Trial, VM, 2026-10-14). popups.lua marks
        -- every open window on its first pass, so this never waits for long.
        -- Not the start warning a slot's Enter raised: it is being closed
        -- quietly, and "Return, 1 of 2" was said anyway (VM, 2026-10-14).
        if first:find("FewerHeroesConfirmWidget", 1, true) and os.clock() < (M.quiet_start_warning_until or 0) then
            virtual.unsaid = nil
        elseif require("popups").was_announced(first) then say_virtual()
        else virtual.unsaid = true end
    end
end

-- The focused button's path as the mod last saw it (dialogue.choice_step).
function M.current_path()
    return current
end

-- The window whose buttons the mod's list holds, or nil (help.lua's I).
function M.virtual_window()
    return virtual and virtual.window or nil
end

-- A window list that stands in front of the views. A ruined room's prompt
-- (WBP_RoomPrompt, "Clear Debris") is part of the ship view: counted as a
-- window, V said "Close the window first" in the ship view (demo, VM,
-- 2026-10-15).
function M.virtual_window_open()
    return M.virtual_active() and not virtual.window:find("WBP_RoomPrompt_C", 1, true)
end

function M.virtual_active()
    if virtual and require("dialogue").active() and not is_confirm(virtual.window) then virtual = nil end
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

-- A combat order the game has locked (bLocked; its icon is dimmed): Surrender
-- and Flee in a fight that cannot be left. Enter on them did nothing, on
-- Casey's machine and in the VM (2026-10-15).
function M.wheel_locked(b)
    local ok, locked = pcall(function()
        return b:GetClass():GetFName():ToString():find("^WBP_RadialButtonCombat") ~= nil and b.bLocked == true
    end)
    return ok and locked
end

-- A ring's Back: its click closed the whole order wheel from a sub-page
-- (Defensive Actions, Casey's machine, 2026-10-16). GoBackToLastMenu goes
-- up one level, and closes the ring from the top (construction.lua).
local function ring_back(path)
    local ring = path and path:match("^(.-WBP_RadialMenu_C_%d+)%.WidgetTree_%d+%.BackButton$")
    if not ring then return false end
    local menu = StaticFindObject(ring)
    if menu and menu:IsValid() and pcall(function() menu:GoBackToLastMenu() end) then
        print("[VoyagerAccess] radial: back one level\n")
        return true
    end
    return false
end

function M.virtual_enter()
    local b = virtual and resolve(virtual.buttons[virtual.index])
    if not b then return end
    if ring_back(virtual.buttons[virtual.index]) then return end
    -- A room button the game will ignore says why instead of clicking
    -- (the Engineering Office's Add work team at its limit, 2026-10-16).
    -- (A trade offer that cannot be paid can still be dismissed.)
    if not virtual.buttons[virtual.index]:find("TradeOff", 1, true) then
        local okl, l = pcall(label_for, b, virtual.buttons[virtual.index])
        local why = okl and type(l) == "string" and l:match("Not possible: ([^%.]+)")
        if why then
            speech.say("Not possible: " .. why, true)
            return
        end
    end
    if M.wheel_locked(b) then
        speech.say("Not available now", true)
        return
    end
    print("[VoyagerAccess] enter: window button " .. virtual.buttons[virtual.index] .. "\n")
    click(b)
    -- DARKER and BRIGHTER only move a bar; the bar's own widgets do not
    -- hold the value, the engine's display gamma does (2026-10-14).
    local name = virtual.buttons[virtual.index]:match("([^%.]+)$")
    if name == "GammaUpButton" or name == "GammaDownButton" then
        local ok, g = pcall(function() return FindFirstOf("GameEngine").DisplayGamma end)
        if ok and type(g) == "number" then speech.say(string.format("Gamma %.1f", g), true) end
    end
end

-- "2 of 5" for buttons the game lists with no count. A forum player could
-- not tell whether they had heard a whole menu (2026-10-15); the main
-- menu, a room's buttons and the pause menu gave no count. Buttons are
-- grouped by the nearest panel holding two or more of them, so a room's
-- Power, Dismantle and Upgrade count together and its tab bar does not.
local positions = {}   -- button path -> "2 of 5"
function M.number_buttons(all, all_names)
    -- Only buttons really on screen: a room's other tab pages are in the
    -- tree too, and the Heroes tab's one slot was "6 of 6".
    local list, names = {}, {}
    for i, b in ipairs(all) do
        -- Nor the Workshop's crafting status, a button that can never take
        -- focus: one blueprint was "2 of 2" (VM, 2026-10-16).
        local status = false
        pcall(function()
            status = all_names[i]:find("%.CraftingButton$") ~= nil and not b:IsInteractionEnabled()
        end)
        if require("screen").shown(b) and not status then
            list[#list + 1] = b
            names[#names + 1] = all_names[i]
        else
            positions[all_names[i]] = nil
        end
    end
    local chains = {}
    for i, b in ipairs(list) do
        local chain, set = {}, {}
        local node, hops = up_one(b), 0
        while node and hops < 64 do
            local p = path_of(node)
            chain[#chain + 1] = p
            set[p] = true
            node, hops = up_one(node), hops + 1
        end
        chains[i] = { chain = chain, set = set }
    end
    for i = 1, #list do
        positions[names[i]] = nil
        -- An event's CONTINUE was counted with the HUD's own buttons
        -- ("CONTINUE, 16 of 16", VM, 2026-10-15): a button that is not the
        -- HUD's does not count the HUD's.
        local in_hud = names[i]:find("WBP_HUD_C_", 1, true) ~= nil
        -- Nor a room's tab bar: a damaged Aeroshuttle Bay's only action was
        -- "Repair, 6 of 6" with the five tab buttons (VM, 2026-10-15).
        local function tab(n) return n:find("TabButton$") ~= nil end
        local is_tab = tab(names[i])
        for _, a in ipairs(chains[i].chain) do
            local group = {}
            for j = 1, #list do
                if chains[j].set[a] and (in_hud or not names[j]:find("WBP_HUD_C_", 1, true))
                    and (is_tab or not tab(names[j])) then
                    group[#group + 1] = j
                end
            end
            if #group >= 2 then
                -- Side-by-side columns (the main menu, its profiles and the
                -- save window in one HorizontalBox) are not one list: "NEW
                -- CAMPAIGN, 11 of 11". When another column has several
                -- buttons, a button alone in its column gets no count.
                local columns = false
                local cls = "?"
                pcall(function() cls = StaticFindObject(a):GetClass():GetFName():ToString() end)
                if cls == "HorizontalBox" then
                    local per = {}
                    for _, j in ipairs(group) do
                        local ch = chains[j].chain
                        local below = nil
                        for k, x in ipairs(ch) do if x == a then below = ch[k - 1] or names[j] end end
                        per[below or names[j]] = (per[below or names[j]] or 0) + 1
                    end
                    for _, n in pairs(per) do if n >= 2 then columns = true end end
                end
                if #group <= 40 and not columns then
                    for k, j in ipairs(group) do
                        if j == i then positions[names[i]] = k .. " of " .. #group end
                    end
                end
                break
            end
        end
    end
end

-- The count for a focused button, or nil.
function M.position_of(path)
    return path and positions[path] or nil
end

-- The label with its count after the first sentence, before any long
-- description ("Normal Food Rations, morale 0, selected, 2 of 3. 1 Food
-- feeds ..."), when it has no count of its own.
local function with_position(label, path)
    -- An empty label is said later by its own module (ring segments after
    -- the hover): a count alone came out as ", 1 of 6" (VM, 2026-10-15).
    -- A label with its own count keeps it ("Combat slot 1 of 3"); a value
    -- such as "health 25 of 25" is not a count (it cost the repair page its
    -- count, VM, 2026-10-16).
    if not (label and positions[path]) or label == "" or label:gsub("health %d+ of %d+", ""):find("%d+ of %d+") then return label end
    -- Just after a room's tab switch the old page still counts as shown, and
    -- the Heroes tab's one slot was "6 of 6": no count then.
    if os.clock() - (require("rooms").tab_switched_at or -100) < 0.6 then return label end
    local head, rest = label:match("^(.-)%.%s+(.+)$")
    -- Not after a short abbreviation such as "Lvl." (review, 2026-10-15).
    if head and rest and not head:match("%f[%a]%u%l?%l?$") then
        return head .. ", " .. positions[path] .. ". " .. rest
    end
    return (label:gsub("[%.,]%s*$", "")) .. ", " .. positions[path]
end

local function wire_rows(path)
    BUTTON_CLASS = BUTTON_CLASS or StaticFindObject("/Script/CommonUI.CommonButtonBase")
    USER_WIDGET = USER_WIDGET or StaticFindObject("/Script/UMG.UserWidget")
    PANEL = PANEL or StaticFindObject("/Script/UMG.PanelWidget")
    -- The top of the button's real parent chain, not of its name: the away
    -- team hero buttons are named as top-level widgets but sit in a panel
    -- inside the loadout ("1 of 1" in the log, 2026-10-11).
    -- The difficulty window and Q Trials setup wire their own lists.
    if require("difficulty").handles(path) or require("qtrials").handles(path) then return end
    local root = resolve(path)
    if not root then return end
    for _ = 1, 64 do
        local up = up_one(root)
        if not up then break end
        root = up
    end
    local all = {}
    buttons_in(root, all, 0)
    -- The warp core tiers move by the mod's own Up and Down (warpcore.lua);
    -- wired here as well, one key moved twice (Gray Mode to Tier 2,
    -- 2026-10-14).
    local list = {}
    for _, b in ipairs(all) do
        if not require("warpcore").handles(path_of(b)) then list[#list + 1] = b end
    end
    local names = {}
    for i, b in ipairs(list) do names[i] = path_of(b) end
    local key, sig = path_of(root), table.concat(names, "|")
    -- Counted on every focus change: a room's tab pages switch without the
    -- button list changing, and counts made as the window opened were stale.
    pcall(function() M.number_buttons(list, names) end)
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
    -- A hero list (the slot's picker) ends at its last hero: Down went on to
    -- "start mission" (2026-10-14).
    local away = require("awaymission")
    local function hero(i) return away.is_hero_button(names[i]) end
    for i = 1, #list - 1 do
        if hero(i) ~= hero(i + 1) then
            if hero(i) then list[i]:SetNavigationRuleBase(NAV_DOWN, 3) end
            if hero(i + 1) then list[i + 1]:SetNavigationRuleBase(NAV_UP, 3) end
        elseif in_row[i] or in_row[i + 1] then
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
    -- Leaving the Q Trials setup: its title comes again on the next visit.
    if not require("qtrials").handles(path) then require("qtrials").away() end
    local work = require("rooms").workteam_label(path) or require("rooms").serving_label(path)
        or require("rooms").research_label(path)
    local cls = b:GetClass():GetFName():ToString()
    if work then
        label = work
    elseif require("difficulty").handles(path) then
        -- Says ", selected" itself, on presets only (difficulty.lua).
        return require("difficulty").label(b, path)
    elseif require("qtrials").handles(path) then
        return require("qtrials").label(b, path)
    elseif cls == "WBP_IncomingCall_List_Button_C" then
        local t = b.NotificationText
        local ok, s = pcall(function() return t:GetText():ToString() end)
        label = "Incoming call: " .. ((ok and s ~= "") and s or "unnamed")
    elseif cls == "WBP_LeaveSectorEntry_C" then
        label = require("popups").leave_sector_entry(b)
    elseif path:find("WBP_MetaProgressionReward_C_%d+%.WidgetTree_%d+%.Button$") then
        label = require("popups").meta_reward_label(b, path)
    elseif path:find("AutoResolveWidget%.WidgetTree_%d+%.Button_Torpedo%a+$") then
        -- "+" and "-" beside the torpedo count; said with the count and the
        -- survival chance they change (VM, 2026-10-15).
        local win = path:match("^(.-AutoResolveWidget)%.")
        local t = win and require("popups").auto_resolve_text(win) or ""
        local tail = (t:match("(Survival chance [^%.]+)") or "") .. ". " .. (t:match("(Torpedoes added [^%.]+)") or "")
        label = (path:find("Add$") and "Add torpedo" or "Remove torpedo") .. ". " .. tail
    elseif cls == "WBP_AeroShuttleBay_TradeOffer_C" then
        label = require("rooms").trade_offer_label(b)
    elseif cls == "WBP_ResourceSelectionButton_C" then
        -- A Cargo Bay's storage choice: only "+50" is text, the resource is
        -- its Icon (MI_UI_Duranium; VM, 2026-10-15). "Duranium, +50 storage".
        local res = nil
        pcall(function()
            local img = b.Icon
            if not (img and img:IsValid()) then return end
            local ro = img.Brush.ResourceObject
            if ro and ro:IsValid() then res = ro:GetFName():ToString():match("^MI_UI_(%a+)") end
        end)
        label = with_value(label_of(path), b)
        if res and label then label = res:gsub("(%l)(%u)", "%1 %2") .. ", " .. label:gsub("%.$", "") .. " storage" end
    elseif cls == "WBP_Shuttle_Status_Button_C" then
        label = require("rooms").shuttle_label(b, path) or with_value(label_of(path), b)
    elseif cls == "WBP_SectorExitBonusFuel_Button_C" then
        label = require("popups").bonus_fuel_label(b)
    elseif cls == "WBP_RadialButton_C" then
        -- Said after the hover, with the centre's details (radial_focus);
        -- the cached text here was said a second time (2026-10-14).
        label = ""
    elseif b:GetClass():GetFName():ToString() == "WBP_POISelectableOption_C" then
        label = require("events").option_label(b)
    elseif require("combat").handles(b, path) then
        label = require("combat").button_label(b, path)
    elseif b:GetClass():GetFName():ToString() == "WBP_CombatAllyButton_C" then
        label = require("rooms").ally_label(b)
    elseif b:GetClass():GetFName():ToString() == "WBP_MultipleChoice_Button_C" then
        -- A side mission offer's options: the wording is rich text the
        -- plain label missed, so the options were silent (2026-10-14).
        local texts = {}
        local prefix = path .. "."
        for _, cls in ipairs({ "RichTextBlock", "TextBlock" }) do
            for _, t in ipairs(FindAllOf(cls) or {}) do
                local tp = t:IsValid() and path_of(t)
                if tp and tp:sub(1, #prefix) == prefix and require("screen").shown(t) then
                    local ok, s = pcall(function() return t:GetText():ToString() end)
                    if ok then s = require("text").prep(s) end  -- icons beside numbers (text.lua)
                    s = ok and s:gsub("<[^>]*/>", ""):gsub("<[^>]*>", ""):gsub("%[([^%]]*)%]", "%1"):gsub("%s+", " ")
                        :gsub("%s+([%.,])", "%1"):match("^%s*(.-)%s*$") or ""
                    if s ~= "" then texts[#texts + 1] = s end
                end
            end
        end
        label = table.concat(texts, ". ")
        if label == "" then label = nil end
        if label and not b:GetIsEnabled() then label = label:gsub("%.$", "") .. ", unavailable" end
        -- "1 of 2": two offer options sounded like one going on (Excess
        -- Power, VM, 2026-10-15).
        if label then
            pcall(function()
                local list = b:GetParent()
                local n, index = 0, nil
                for i = 0, list:GetChildrenCount() - 1 do
                    local c = list:GetChildAt(i)
                    if c and c:IsValid() and c:GetClass():GetFName():ToString() == "WBP_MultipleChoice_Button_C"
                        and require("screen").shown(c) then
                        n = n + 1
                        if c:GetFullName() == b:GetFullName() then index = n end
                    end
                end
                if index and n > 1 then label = label:gsub("%.$", "") .. ", " .. index .. " of " .. n end
            end)
        end
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
    -- Choice groups (Performance Selection's LOW to EPIC, profiles, settings
    -- tabs) show the current choice only by colour: the game keeps it
    -- Selected. Say so (2026-10-14, the VM run).
    -- Not on a room's buttons: the power button is Selected while on and
    -- already says so ("Stellar Cartography on., selected", 2026-10-14).
    -- Nor on dialogue choices: the first one is Selected by default and read
    -- "Destroy the Array, selected" before anything was picked (2026-10-14).
    if label and not label:find("selected", 1, true) and not require("rooms").is_module_button(path)
        and not path:find("AutoResolveWidget", 1, true)
        and not require("dialogue").is_choice(path) then
        local ok, sel = pcall(function() return b:GetSelected() end)
        -- Only in a group: a lone story card CONTINUE is Selected too and
        -- was read "CONTINUE, selected" (2026-10-14).
        local grouped = false
        pcall(function()
            BUTTON_CLASS = BUTTON_CLASS or StaticFindObject("/Script/CommonUI.CommonButtonBase")
            local parent = b:GetParent()
            local n = 0
            for i = 0, parent:GetChildrenCount() - 1 do
                local ch = parent:GetChildAt(i)
                if ch and ch:IsValid() and ch:IsA(BUTTON_CLASS) then n = n + 1 end
            end
            grouped = n >= 2
        end)
        if ok and sel and grouped then label = label:gsub("%.$", "") .. ", selected" end
    end
    -- The order wheel's repair page put the system's health first with no
    -- word for it: "49, Repair Weapons" (VM, 2026-10-15).
    if label and path:find("Radial", 1, true) then
        label = label:gsub("^(%d+), (Repair [%a ]+)", "%2, health %1")
        label = label:gsub("^(Repair [%a ]+), (%d+)", "%1, health %2")
        local okr, full = pcall(require("combat").repair_label, label)
        if okr and full then label = full end
    end
    -- Surrender's cost shows only while the mouse is over it
    -- (WBP_SurrenderCost in the loadout's ResourceRewardBundle, "40
    -- Duranium", Q Trials ambush, VM, 2026-10-15).
    if label and path:find("HeroLoadout", 1, true) and path:find("%.SurrenderButton$") then
        local costs = {}
        local prefix = path:match("^(.-%.HeroLoadout)%.")
        for _, w in ipairs(FindAllOf("WBP_SurrenderCost_C") or {}) do
            local wp = w:IsValid() and path_of(w)
            if wp and prefix and wp:sub(1, #prefix + 1) == prefix .. "." then
                local oka, a = pcall(function() return w.ResourceAmountTextBlock:GetText():ToString() end)
                local okn, n = pcall(function() return w.ResourceNameTextBlock:GetText():ToString() end)
                if oka and okn and a ~= "" then costs[#costs + 1] = a .. " " .. n end
            end
        end
        if #costs > 0 then label = label:gsub("%.$", "") .. ". Costs " .. table.concat(costs, ", ") end
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
    -- Focus left behind a window whose own buttons cannot take it: the
    -- arrows moved the Q Trial profiles under the warning (2026-10-14).
    -- Park it, so the window's button list takes the keys.
    if b then
        local fw = focusless_window()
        local bp = fw and path_of(b)
        if bp and bp:sub(1, #fw + 1) ~= fw .. "." then
            M.park_focus()
            b = nil
        end
    end
    -- In battle the hidden hero setup's slot kept keyboard focus, so the
    -- order wheel's button list never came up (2026-10-14).
    if b and require("combat").active() and not require("screen").shown(b) then b = nil end
    -- Main menu: Down past the last setting moved focus to the DLC tiles
    -- behind Settings, and after leaving Settings, to its hidden tabs
    -- (full game, 2026-10-14). Focus on a hidden main menu button goes
    -- back to the last button that was on screen, unread.
    if b and not require("screen").shown(b) then
        local p = path_of(b) or ""
        if p:find("WBP_MainMenu", 1, true) or p:find("LCARS_Button_MainMenu", 1, true) then
            local back = last_real and resolve(last_real)
            if back and back ~= b and require("screen").shown(back) then
                print("[VoyagerAccess] focus: hidden " .. p:match("([^%.]+)$") .. ", back to " .. last_real:match("([^%.]+)$") .. "\n")
                back:SetFocus()
            end
            return
        end
    end
    -- While a mod list is open the game still moves menu focus on Up and
    -- Down; say nothing about it and park focus again, or the menu talks
    -- over the list ("bleeding through", 2026-10-11).
    if mod_list_open() then
        if b then M.park_focus() end
        return
    end
    if not b then b = focus_first_run_screen() end
    if not b then
        local okr, r = pcall(focus_radial)
        if okr then b = r end
    end
    if b then
        virtual = nil
        last_real = path_of(b)
    elseif not current and not restore_focus() then
        track_unfocused_window()
    end
    local path = b and path_of(b) or nil
    ticks = ticks + 1
    -- After an optional dialogue choice the choices come back on the same
    -- button, focus never changes, and nothing was said; Enter then took the
    -- next choice unheard, three in a row (distress call, VM, 2026-10-15).
    -- A choice that shows again is read again, with the Enter guard.
    -- Polls while the choice is hidden can return early above, so the test
    -- is how long since it was last seen on screen.
    local is_choice = path and require("dialogue").is_choice(path)
    local shown_now = is_choice and b and require("screen").shown(b) or false
    if path and path == current and is_choice then
        if shown_now and os.clock() - choice_seen_at > 0.6 then
            focus_tick = ticks
            local label = label_for(b, path)
            print("[VoyagerAccess] focus: choices back: " .. tostring(label) .. "\n")
            if label then speech.say(label, true) end
        end
        if shown_now then choice_seen_at = os.clock() end
        return
    end
    if shown_now then choice_seen_at = os.clock() end
    if path == current then return end
    -- In the full game the item whose panel was open stays selected after
    -- Backspace, with its panel still open beside the menu, and Down from
    -- EXIT went into that panel (Settings' tabs); Up from Settings' first tab
    -- went out to EXIT (demo and full game, 2026-10-14). Navigation rules
    -- were ignored, so focus is taken back: Up and Down never cross between
    -- the main menu and its panel. Enter and Right still go in.
    -- The part of the main menu a button belongs to. Campaign and Q Trials
    -- profiles sit straight in the menu's own tree like its buttons, so Down
    -- from EXIT went into "Q Trial 01" and on to the DLC tiles (Casey,
    -- 2026-10-14); they are a part of their own.
    local function zone(p)
        local first = p:match("WBP_MainMenu_C_%d+%.WidgetTree_%d+%.([%w_]+)")
        if not first then return "outside" end
        -- Only in the full game: the demo's profiles are the top of the
        -- main menu itself (Down stopped at Profile 3, VM, 2026-10-14).
        if first:find("^WBP_Button_SaveProfile_C") then
            local tree = p:match("^(.-WBP_MainMenu_C_%d+%.WidgetTree_%d+)%.")
            if tree and resolve(tree .. ".CampaignButton") then return "profiles" end
        end
        if p:find("WBP_MainMenu_C_%d+%.WidgetTree_%d+%.[%w_]+$") then return "main" end
        return first
    end
    -- The game can move focus on Down before the mod reads that Down from
    -- keys.txt, so a crossing did not look like an arrow (1 run in 3 in the
    -- VM, 2026-10-14). Inside the menu's own tree a crossing is allowed only
    -- just after Enter, Right, Left, Backspace or Escape.
    local inside = zone(current or "") ~= "outside" and zone(path or "") ~= "outside"
    local by_arrow = ticks - arrow_tick <= 2 or (inside and ticks > go_in_until)
    if path and current and by_arrow and resolve(current)
            and zone(current) ~= zone(path)
            and (current:find("WBP_MainMenu", 1, true) or current:find("LCARS_Button_MainMenu", 1, true)) then
        print("[VoyagerAccess] focus: arrow left the menu, staying\n")
        resolve(current):SetFocus()
        last_real = current
        return
    end
    crumb.at("focus: changed to " .. tostring(path))
    -- When focus first reaches a set of dialogue choices (not when it moves
    -- between them): see the Enter guard in activate().
    local was_choice = current ~= nil and require("dialogue").is_choice(current)
    current = path
    -- The battle setup's Start action follows focus (combat.lua).
    if path and path:find(".HeroLoadout.", 1, true) then pcall(require("combat").setup_sync) end
    if path and not was_choice and require("dialogue").is_choice(path) then focus_tick = ticks end
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
    -- Down on a tab's last setting jumped up to the tab row ("Severity",
    -- then "Accessibility, selected", full game, 2026-10-14). It stops there.
    if is_setting(b) then pcall(function()
        local parent = b:GetParent()
        local last = nil
        for _, s in ipairs(FindAllOf("WBP_Setting_C") or {}) do
            if s:IsValid() and live(s) and require("screen").shown(s) then
                local sp = s:GetParent()
                if sp and sp:IsValid() and parent and sp:GetFullName() == parent:GetFullName() then last = s end
            end
        end
        if last and path_of(last) == path then b:SetNavigationRuleBase(3, 3) end   -- Down: Stop
    end) end
    if is_setting(b) and is_heading(b) and skip_heading(b) then return end
    -- awaymission.lua moves the game's focus along its own list and says
    -- each item itself; saying the focused button too would double it.
    if (path:find("WBP_Dialogue_Choice_AwayMission_C", 1, true) or path:find("STVAwayMissionHeroSelectionPlaque", 1, true)
        or path:find("WBP_AwayMission_Choice_HeroSelection", 1, true)) and require("awaymission").mission_active() then
        return
    end
    crumb.at("focus: label of " .. path)
    if b:GetClass():GetFName():ToString() == "WBP_RadialButton_C" then pcall(M.radial_focus, b, path) end
    local label = label_for(b, path)
    if section_prefix then
        label = label and (section_prefix .. ", " .. label) or section_prefix
        section_prefix = nil
    end
    print(string.format("[VoyagerAccess] focus: %s | %s\n", tostring(label), path))
    -- The pause menu that Escape opened behind a closing mod list is
    -- resumed at once; "Closed. RESUME" was said anyway (VM, 2026-10-15).
    if path:find("WBP_PauseMenu_C", 1, true) and os.clock() < (M.undo_pause_until or 0) then return end
    -- go_back is putting a room's hero back and says the result itself.
    if os.clock() < (M.hush_focus_until or 0) then return end
    -- An event between its choice and its result (popups.lua).
    if path:find("WBP_POIMultipleChoice_C", 1, true)
        and (os.clock() < (require("popups").result_pending_until or 0) or require("popups").event_unread(path)) then
        print("[VoyagerAccess] focus: held until the event result is read\n")
        return
    end
    -- A story card's Continue: dialogue.lua says "Continue" after the card.
    if path:find("WBP_Dialogue_Popup%.WidgetTree_%d+%.ContinueButtonStory$") then return end
    -- While the game's chances are being read, the option waits: it was
    -- said with the mod's own chances, then again with the game's (Looted
    -- Wreckage, Q Trials, VM, 2026-10-15). The sweep says it at the end.
    if path:find("WBP_POIMultipleChoice_C", 1, true) and require("events").sweeping_now() then return end
    -- A room window or event that has just opened: popups.lua reads the
    -- window and then says this button. Said here as well, it came three
    -- times over: "Life Support off. Life Support, inactive. ... Life
    -- Support off." (2026-10-15).
    -- A room's buttons are in their own module widgets (WBP_UpgradeModule),
    -- not under the window's path, so any such window still unread counts.
    local popups = require("popups")
    local okm, map = pcall(function() return require("system").active() end)
    -- A side mission offer too: its button came before its text ("Good
    -- idea, let's build a BATTERY COMPARTMENT..." then Excess Power, VM,
    -- 2026-10-15).
    -- And the first-launch screens: "CONFIRM" came before "Performance
    -- Selection" when focus was polled first (demo, VM, 2026-10-15).
    -- And a battle's result: "Proceed" came before "Combat result:
    -- victory..." (Q Trials ambush, VM, 2026-10-15).
    for _, cls in ipairs({ "WBP_RoomManagementV2_C", "WBP_POIMultipleChoice_C", "WBP_MultipleChoiceWidget_C",
                           "WBP_FirstPerformanceSelection_C", "WBP_GammaCorrection_C", "WBP_BattleResultLCARS_C",
                           "WBP_SandboxSectorResult_C", "WBP_CombatAutoResolve_C" }) do
        if not (cls == "WBP_RoomManagementV2_C" and okm and map) then
            for _, w in ipairs(FindAllOf(cls) or {}) do
                if w:IsValid() and live(w) and require("screen").shown(w) and not popups.was_announced(path_of(w)) then
                    return
                end
            end
        end
    end
    label = with_position(label, path)
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
-- ESTVMainMenuContentPanelItems index, looked up by name: the full game
-- numbers them differently (Settings 1, DLC 2, CampaignProfiles 3,
-- CampaignSaves 4, SandboxProfiles 5, SandboxSaves 6, 2026-10-14), so the
-- demo's save panel number opened the DLC panel there. The fallbacks are the
-- demo's: 1 = settings and 2 = save panel are proven, 0 is untested (a crash
-- followed calling it).
local panel_ids = nil
local function panel(name, fallback)
    if not panel_ids then
        panel_ids = {}
        local e = StaticFindObject("/Script/STVoyager.ESTVMainMenuContentPanelItems")
        if e and e:IsValid() then
            e:ForEachName(function(n, v)
                local s = n:ToString()
                panel_ids[s:match("::(.+)$") or s] = v
            end)
        end
    end
    return panel_ids[name] or fallback
end

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
    -- The full game has Campaign and Q Trials profiles, each with its own
    -- saves panel; a profile under SandboxProfileButtonParent is Q Trials.
    local sandbox = false
    pcall(function()
        local box = menu.SandboxProfileButtonParent
        sandbox = box and box:IsValid() and path_of(b:GetParent()) == path_of(box)
    end)
    -- The one save window serves both; without bIsSandbox it offered NEW
    -- CAMPAIGN for a Q Trial profile (2026-10-14). Demo: no such field.
    pcall(function() w.bIsSandbox = sandbox and true or false end)
    -- The demo has one save panel, SectorSave (2).
    if sandbox then
        menu:ShowContentPanel(panel("SandboxSaves", 2))
    else
        menu:ShowContentPanel(panel("CampaignSaves") or panel("SectorSave", 2))
    end
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
    local name = b:GetFName():ToString()
    if name == "SettingsButton" then
        menu:ShowContentPanel(panel("Settings", 1))
        return menu
    end
    -- Full game only: CAMPAIGN and Q TRIALS open their three profiles; the
    -- mod's Enter only selected CAMPAIGN and nothing opened (2026-10-14).
    if (name == "CampaignButton" and panel("CampaignProfiles")) or (name == "SandboxButton" and panel("SandboxProfiles")) then
        menu:ShowContentPanel(panel(name == "CampaignButton" and "CampaignProfiles" or "SandboxProfiles"))
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
    -- The Enter that moves the last line on can land just as the choices
    -- come up, and it picked "Choice 1" before it was heard (twice,
    -- 2026-10-14). Within a second of the choices appearing, Enter says
    -- the focused choice instead of picking it.
    if choice and require("screen").shown(choice) and ticks - focus_tick < 10 then
        local label = label_for(choice, current)
        print("[VoyagerAccess] enter: choice just appeared, reading it\n")
        if label then speech.say(label, true) end
        return
    end
    if choice and require("screen").shown(choice) then
        local cpath = current:match("^(.-WBP_Dialogue_Choice_Sector_C_%d+)") or current:match("^(.-WBP_Dialogue_Choice_C_%d+)")
        local c = cpath and resolve(cpath)
        local target = c and c.RightButton
        if not (target and target:IsValid()) then target = resolve(current) end
        if target then
            print("[VoyagerAccess] enter: choice " .. tostring(current) .. "\n")
            -- The Array's "Destroy the Array or go home" choice is a hold
            -- button (bRequiresHold); a click did nothing, fourteen times
            -- (2026-10-14). Hold it as Wait One Cycle is held.
            local okh, hold = pcall(function() return target.bRequiresHold end)
            if okh and hold then
                speech.say("Holding", true)
                target:HandleButtonPressed()
                local held = path_of(target)
                ExecuteInGameThreadWithDelay(2500, function()
                    pcall(function()
                        local nb = resolve(held)
                        if nb then nb:HandleButtonReleased() end
                        print("[VoyagerAccess] enter: released choice " .. held .. "\n")
                    end)
                end)
                return
            end
            click(target)
            return
        end
    end
    local focused = resolve(current)
    local on_screen = focused ~= nil and require("screen").shown(focused)
    -- The pause menu (and the Audio and Gamma windows it opens) sits over
    -- the dialogue: Enter on its MAIN MENU continued the dialogue instead
    -- (2026-10-14, full game).
    local over_dialogue = on_screen and (current:find("WBP_PauseMenu_C", 1, true)
        or current:find("WBP_SettingsWindow_C", 1, true) or current:find("WBP_GammaCorrection_C", 1, true))
    if dialogue.active() and not over_dialogue and not (on_screen and dialogue.contains(current)) then
        dialogue.continue()
        return
    end
    local b = resolve(current)
    -- The battle setup rebuilds its slots after a hero is chosen, so the
    -- slot just announced was gone by path; Enter then reached the game as
    -- Start and raised "unassigned slots" (VM, 2026-10-14). Ask again.
    if not b then
        local fb = focused_button()
        if fb and require("screen").shown(fb) then
            current = path_of(fb)
            b = fb
            print("[VoyagerAccess] enter: focus looked up again: " .. current .. "\n")
        end
    end
    -- The away team's slots lose keyboard focus about a second after a hero
    -- is chosen; Enter then reached the game as Start Mission ("unassigned
    -- slots", VM, 2026-10-14). The last button that had focus is used.
    if not b and last_real then
        local lb = resolve(last_real)
        if lb and require("screen").shown(lb) then
            current = last_real
            b = lb
            pcall(function() lb:SetFocus() end)
            print("[VoyagerAccess] enter: using the last focused button: " .. current .. "\n")
        end
    end
    if not b then
        print("[VoyagerAccess] enter: no focused button\n")
        return
    end
    -- An Aeroshuttle trade offer: its TRADE and DISMISS buttons cannot be
    -- reached with the arrows (VM, 2026-10-15). Enter puts focus on TRADE,
    -- or on DISMISS when the trade cannot be paid for.
    if b:GetClass():GetFName():ToString() == "WBP_AeroShuttleBay_TradeOffer_C" then
        local target = nil
        pcall(function()
            local t, d, c = b.TradeBtn, b.DismissBtn, b.CollectButton
            -- A finished trade shows only COLLECT (VM, 2026-10-16).
            if c and c:IsValid() and require("screen").shown(c) and c:GetIsEnabled() then target = c
            elseif t and t:IsValid() and t:GetIsEnabled() then target = t
            elseif d and d:IsValid() and d:GetIsEnabled() then target = d end
        end)
        if target then
            if back_stack[#back_stack] ~= current then back_stack[#back_stack + 1] = current end
            target:SetFocus()
        else
            speech.say("Nothing can be done with this offer", true)
        end
        return
    end
    -- A room button that cannot be used: Enter did nothing and said
    -- nothing (Dismantle without life support, VM, 2026-10-15).
    if require("rooms").is_module_button(current) then
        local okl, l = pcall(label_for, b, current)
        local why = okl and type(l) == "string" and l:match("Not possible: ([^%.]+)")
        if why then
            speech.say("Not possible: " .. why, true)
            return
        end
    end
    -- A Q Trial reward card: say that it was chosen and the count.
    if current:find("WBP_MetaProgressionReward_C_%d+%.WidgetTree_%d+%.Button$") then
        local popups = require("popups")
        popups.meta_chosen = current
        ExecuteInGameThreadWithDelay(300, function()
            pcall(function()
                local n = popups.meta_reward_count()
                speech.say("Chosen" .. (n ~= "" and (", rewards selected " .. n) or "") .. ". Confirm is at the end of the list.", true)
            end)
        end)
    end
    print("[VoyagerAccess] enter: clicking " .. tostring(current) .. "\n")
    -- The save window's Delete Profile only became "selected" on Enter; a
    -- real click opened its warning (full game, VM, 2026-10-15). The
    -- window's own TryDeleteCurrentProfile is called. (Restart Sector's
    -- ordinary click does open its list of sector saves, checked in the
    -- demo; ClickedSectorSaveButton did nothing.)
    if current:find("SectorSaveWindow", 1, true) then
        local name = current:match("([^%.]+)$")
        local handler = name == "DeleteAllSavesButton" and "TryDeleteCurrentProfile" or nil
        if handler then
            for _, w in ipairs(FindAllOf("WBP_LoadSectorSaveWindow_C") or {}) do
                if w:IsValid() and live(w) and require("screen").shown(w) then
                    print("[VoyagerAccess] enter: save window " .. handler .. "\n")
                    local ok, err = pcall(function() w[handler](w) end)
                    if not ok then print("[VoyagerAccess] enter: " .. tostring(err) .. "\n") end
                    return
                end
            end
        end
    end
    -- The room's hero when its hero list is opened: closing the list
    -- without a choice leaves the room with no hero (see go_back).
    if current:find("WBP_HeroModule_C_%d+%..*OpenSelectionButton$") then
        local okl, l = pcall(label_for, b, current)
        M.room_hero_before = okl and type(l) == "string" and l:match("^Assigned hero: ([^%.]+)") or nil
    end
    -- Enter on a settings row opens nothing, so it is not a place to go back to.
    if not is_setting(b) and back_stack[#back_stack] ~= current then
        back_stack[#back_stack + 1] = current
    end
    -- A settings category whose page is already showing ignores the click
    -- (selection does not change, so the game does nothing), so focus the
    -- page's own desired target instead (proven 2026-10-10 on Graphics).
    -- The tab buttons' outer is the game instance, not the window, so the
    -- shown settings window is looked up instead (2026-10-14: walking the
    -- outers never matched and Enter on the open tab did nothing).
    -- A ring segment is under the mouse (radial_focus hovered it), and the
    -- game's own Enter selects the hovered segment; clicking it as well
    -- could do the action twice. So click only if the ring is still open,
    -- with the same segment, a moment later (2026-10-14).
    if ring_back(current) then return end
    -- COLLECT on a finished trade: the goods arrive with no word (VM,
    -- 2026-10-16). Say what came, from the offer, after the click.
    local offer_path = current and current:match("^(.-WBP_AeroShuttleBay_TradeOff[%w_]*)%.WidgetTree_%d+%.CollectButton$")
    if offer_path then
        local got = nil
        pcall(function()
            local offer = StaticFindObject(offer_path)
            got = offer and require("rooms").trade_offer_label(offer):match("You get ([^%.]+)")
        end)
        print("[VoyagerAccess] enter: collecting trade " .. tostring(got) .. "\n")
        local current_collect = current
        click(b)
        -- Said only once the button has gone (review, 2026-10-16).
        ExecuteInGameThreadWithDelay(500, function()
            pcall(function()
                local c = StaticFindObject(current_collect)
                if c and c:IsValid() and require("screen").shown(c) then
                    speech.say("Collect did not take", true)
                else
                    speech.say(got and ("Collected: " .. got) or "Collected", true)
                end
            end)
        end)
        return
    end
    if b:GetClass():GetFName():ToString() == "WBP_RadialButton_C" then
        -- A segment the game has locked (bLocked): Clear Debris with no life
        -- support did nothing and said nothing on Enter (VM, 2026-10-15).
        -- Say why, from what the ring said for it ("Clear Debris. No Life
        -- Support. ...").
        local okl, locked = pcall(function() return b.bLocked == true end)
        if okl and locked then
            local said = radial_said[current] or ""
            local name, why = said:match("^([^%.]+)%.%s*([^%.]+)")
            speech.say("Not possible" .. (why and (": " .. why) or "") .. (name and (". " .. name) or ""), true)
            return
        end
        -- A room to build: built at the selected space by the mod, since the
        -- game's own placement needs a mouse click on a slot (2026-10-14).
        local okc, handled = pcall(require("construction").enter, b, radial_said[current])
        if not okc then print("[VoyagerAccess] construction error: " .. tostring(handled) .. "\n") end
        if okc and handled then return end
        local seg = current
        ExecuteInGameThreadWithDelay(400, function()
            pcall(function()
                local nb = resolve(seg)
                if nb and require("screen").shown(nb) and current == seg then
                    print("[VoyagerAccess] radial: clicking " .. seg .. "\n")
                    click(nb)
                end
            end)
        end)
        return
    end
    if require("warpcore").handles(current) then require("warpcore").after_enter(current) end
    local window = nil
    if b:GetClass():GetFName():ToString() == "WBP_LCARS_Button_MainMenu_C" then
        for _, w in ipairs(FindAllOf("WBP_SettingsWindow_C") or {}) do
            if w:IsValid() and live(w) and require("screen").shown(w) then window = w end
        end
    end
    local function focus_page()
        local page = window.ContentPanel:GetActiveWidget()
        local target = page and page:IsValid() and page:GetDesiredFocusTarget()
        if target and target:IsValid() then
            target:SetFocus()
            return true
        end
        return false
    end
    if window and b:GetSelected() and focus_page() then return end
    -- A tab not yet open: the click opens its page, and the game then
    -- sometimes moved focus into it and sometimes left it on the tab
    -- (2026-10-14). Move it in, so one Enter always reaches the settings.
    if window then
        click(b)
        local tab = current
        ExecuteInGameThreadWithDelay(400, function()
            pcall(function()
                if current == tab and window:IsValid() then focus_page() end
            end)
        end)
        return
    end
    local menu = open_panel_for(b)
    if menu then
        -- The click moves focus into the panel only once the panel is up;
        -- in the same tick it did nothing, and one poll later it still
        -- failed about half the time (Casey had to press Enter twice), so
        -- poll() waits for the panel animation to finish.
        pending_click = { button = current, menu = path_of(menu), polls = 0 }
    else
        -- A Q Trials hero is chosen or removed with its own announcement.
        if require("qtrials").enter(b, current) then return end
        -- An event option with a hero chosen (Left and Right).
        if require("events").enter(b, current) then return end
        -- A locked sector in Leave Sector: holding it did nothing but say
        -- "Holding" (VM, 2026-10-14). Say why instead.
        if b:GetClass():GetFName():ToString() == "WBP_LeaveSectorEntry_C" then
            local okl, locked = pcall(function() return require("screen").shown(b.Locked_IMG) or b.Affordable == false end)
            if okl and locked then
                speech.say("Cannot leave for this sector yet. " .. require("popups").leave_sector_entry(b), true)
                return
            end
        end
        -- Main menu DLC tiles (WBP_Button_Entitlement_C) are cards: an owned
        -- one does nothing on a click, and its description and new content
        -- are rich text, which the focus label skips. Casey: "none of the
        -- dlc menu items work when pressing enter" (2026-10-14). Enter reads
        -- the card; one not installed is also clicked (Visit Store Page).
        if b:GetClass():GetFName():ToString() == "WBP_Button_Entitlement_C" then
            local function plain(x)
                local ok, s = pcall(function() return x:GetText():ToString() end)
                if not ok or not s then return "" end
                return (s:gsub("<[^>]*>", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
            end
            local parts = { plain(b.DLCTitleText), plain(b.DLCEntitlementState), plain(b.DLCDescription) }
            pcall(function()
                local box = b.FeatureItemParent
                for i = 0, box:GetChildrenCount() - 1 do
                    local f = box:GetChildAt(i)
                    if f and f:IsValid() and require("screen").shown(f) then parts[#parts + 1] = plain(f.Text) end
                end
            end)
            local said = {}
            for _, p in ipairs(parts) do
                if p ~= "" then said[#said + 1] = p:gsub("[%.%s]+$", "") .. "." end
            end
            speech.say(table.concat(said, " "), true)
            if plain(b.DLCEntitlementState) ~= "Installed" then click(b) end
            return
        end
        local before = label_for(b, current)
        local path = current
        -- A hold button (Custom difficulty's Start Game, bRequiresHold)
        -- ignores a click: hold it, as dialogue choices and Wait One Cycle
        -- are held.
        local okh, hold = pcall(function() return b.bRequiresHold end)
        if okh and hold then
            speech.say("Holding", true)
            b:HandleButtonPressed()
            ExecuteInGameThreadWithDelay(2500, function()
                pcall(function()
                    local nb = resolve(path)
                    if nb then nb:HandleButtonReleased() end
                    print("[VoyagerAccess] enter: released " .. path .. "\n")
                end)
            end)
            return
        end
        click(b)
        -- The Science Laboratory's analysis button moves between its
        -- Unexplored and Analysis sections, so the changed-label check below
        -- never fired and Enter said nothing (VM, 2026-10-14).
        if b:GetClass():GetFName():ToString() == "WBP_RoomMgmt_Analyze_Button_C" then
            local started = before and before:find("^Unexplored") ~= nil
            local stopped = before and before:find("^Analysis") ~= nil
            if started or stopped then
                speech.say(started and "Analysis started" or "Analysis stopped", true)
                return
            end
        end
        -- Enter on an away team slot opens its hero picker, but the game
        -- also takes that Enter as "Start away mission" and puts up "You
        -- still have unassigned slots. Continue?" (twice, 2026-10-14). The
        -- mod cannot keep the key from the game, so it closes that warning
        -- with Return when it comes up straight after a slot was opened.
        -- The battle's hero setup does the same (2026-10-14).
        if path:find("WBP_AwayMissionHeroPicker_C_%d+%.") or path:find("HeroPickerTemplate", 1, true)
            or (path:find("%.HeroLoadout%.") and path:find("OpenSelectionButton$")) then
            M.quiet_start_warning_until = os.clock() + 2
            local function dismiss(tries)
                local done = false
                pcall(function()
                    for _, w in ipairs(FindAllOf("WBP_AM_ConfirmStart_C") or {}) do
                        if w:IsValid() and live(w) and require("screen").shown(w) then
                            print("[VoyagerAccess] away: closing the start warning the slot's Enter raised\n")
                            click(w.CloseButton)
                            done = true
                            -- When the warning came first, the slot's click
                            -- was lost and no picker opened: click it again.
                            ExecuteInGameThreadWithDelay(300, function()
                                pcall(function()
                                    local open = false
                                    for _, h in ipairs(require("awaymission").hero_buttons()) do
                                        if h:IsValid() and live(h) and require("screen").shown(h) then open = true end
                                    end
                                    local slot = resolve(path)
                                    if not open and slot then
                                        print("[VoyagerAccess] away: opening the slot again\n")
                                        click(slot)
                                    end
                                end)
                            end)
                        end
                    end
                end)
                if not done and tries > 1 then ExecuteInGameThreadWithDelay(200, function() dismiss(tries - 1) end) end
            end
            -- About 2 s: in battle setup the warning once came after the
            -- old 1 s of tries and stayed up (Q Trial, VM, 2026-10-14).
            ExecuteInGameThreadWithDelay(150, function() dismiss(10) end)
        end
        -- The power button's text changed later than 400 ms (Switch Off on
        -- Life Support, 2026-10-11), so check every 300 ms for 2.4 s.
        local function check(tries)
            local done = true
            pcall(function()
                -- Focus moved on (a settings tab opens its page): the old
                -- button's new text only talked over the new focus
                -- ("Audio, selected" cut off "Master Volume", 2026-10-14).
                if current ~= path then return end
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
            elseif not done and path:find("%.PowerToggleButton$") and current == path then
                -- The game refuses a room it has no power for without a
                -- word (Shield Generator, 57 of 60 in use, 2026-10-14).
                pcall(function()
                    local cm = FindFirstOf("STVConstructionManager")
                    local info = cm:GetWarpcoreInfo()
                    speech.say(string.format("Did not switch. Energy %d, rooms use %d.",
                        info.EnergyAmount, info.EnergyConsumption), true)
                end)
            end
        end
        ExecuteInGameThreadWithDelay(300, function() check(8) end)
    end
end

-- Backspace: return focus to the button Enter was last pressed on. The game
-- has no keyboard Back of its own (Escape does not close the save panel).
local function go_back()
    crumb.at("key: backspace")
    if require("qtrials").back(current) then return end
    -- A hero list (a room's WBP_RoomHeroPickerSelection, the away team's
    -- WBP_AwayMissionHeroPickerSelection): close it the way Escape does,
    -- which puts focus back on the slot or "Assign a hero" ("Nothing to go
    -- back to", demo, VM, 2026-10-15). CloseMenu left the room's button
    -- hidden. The list is found by walking up from the focused hero.
    if current then
        local closed = false
        pcall(function()
            local w, d = resolve(current), 0
            while w and w:IsValid() and d < 10 do
                local cls = w:GetClass():GetFName():ToString()
                if cls:find("HeroPickerSelection_C$") then
                    -- Closing a room's list without a choice takes its hero
                    -- out of the room, with the game's Escape too, and
                    -- clicking that hero in the list takes him out as well:
                    -- Neelix left the Mess Hall on Backspace (VM,
                    -- 2026-10-15). The room has no close button. So the list
                    -- is closed, opened again and the hero chosen again,
                    -- quietly, and the slot is said at the end.
                    local keep = cls:find("Room", 1, true) and M.room_hero_before
                    w:CallBackAction()
                    if keep then
                        print("[VoyagerAccess] back: choosing " .. keep .. " again\n")
                        M.hush_focus_until = os.clock() + 4
                        local function shown_slot()
                            for _, sb in ipairs(FindAllOf("CommonButtonBase") or {}) do
                                if sb:IsValid() and sb:GetFName():ToString() == "OpenSelectionButton" and live(sb)
                                    and sb:GetFullName():find("WBP_HeroModule_C", 1, true) and require("screen").shown(sb) then
                                    return sb
                                end
                            end
                        end
                        local function finish()
                            M.hush_focus_until = 0
                            local okl, l = pcall(M.current_label)
                            speech.say(okl and l or ("Assigned hero: " .. keep), true)
                        end
                        ExecuteInGameThreadWithDelay(400, function()
                            local ok = pcall(function()
                                local sb = shown_slot()
                                if not sb then return finish() end
                                click(sb)
                                ExecuteInGameThreadWithDelay(500, function()
                                    pcall(function()
                                        for _, hb in ipairs(FindAllOf("WBP_RoomHeroSelectionButton_C") or {}) do
                                            local okn, nm = pcall(function() return hb.HeroPlaque.HeroNameText:GetText():ToString() end)
                                            if okn and hb:IsValid() and live(hb) and require("screen").shown(hb)
                                                and nm:match("^%s*(.-)%s*$") == keep then
                                                click(hb)
                                                break
                                            end
                                        end
                                    end)
                                    ExecuteInGameThreadWithDelay(500, function() pcall(finish) end)
                                end)
                            end)
                            if not ok then M.hush_focus_until = 0 end
                        end)
                    end
                    closed = true
                    return
                end
                local p = nil
                pcall(function() p = w:GetParent() end)
                if not (p and p:IsValid()) then pcall(function() p = w:GetOuter() end) end
                w, d = p, d + 1
            end
        end)
        if closed then
            print("[VoyagerAccess] back: hero list closed\n")
            return
        end
    end
    while #back_stack > 0 do
        local path = table.remove(back_stack)
        local b = path ~= current and resolve(path) or nil
        -- Never back into the main menu behind the Q Trials setup: focus
        -- went to NEW Q TRIAL under it (2026-10-14). Escape leaves the setup.
        if b and current and current:find("WBP_Sandbox_Setup_C_", 1, true) and path:find("WBP_MainMenu_C_", 1, true) then
            b = nil
        end
        if b and b:IsVisible() then
            print("[VoyagerAccess] back: " .. path .. "\n")
            b:SetFocus()
            return
        end
    end
    -- On a settings row with nothing stacked (the page was reached by
    -- arrows), go back to the open settings tab (2026-10-14).
    local cur = resolve(current)
    if cur and is_setting(cur) then
        for _, t in ipairs(FindAllOf("WBP_LCARS_Button_MainMenu_C") or {}) do
            if t:IsValid() and live(t) and require("screen").shown(t) and t:GetSelected() then
                t:SetFocus()
                return
            end
        end
    end
    -- On a settings tab with nothing stacked, go back to the main menu's
    -- SETTINGS ("Nothing to go back to" left Casey in Settings, 2026-10-14).
    if current and current:find("LCARS_Button_MainMenu", 1, true) then
        for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
            local p = b:IsValid() and live(b) and path_of(b)
            if p and p:find("WBP_MainMenu_C_%d+%.WidgetTree_%d+%.SettingsButton$") and require("screen").shown(b) then
                print("[VoyagerAccess] back: main menu SETTINGS\n")
                b:SetFocus()
                return
            end
        end
    end
    -- In the main menu's DLC panel, close it as Escape does (its back
    -- button) and return to the DLC button ("Nothing to go back to",
    -- Casey, 2026-10-14).
    if current and current:find("%.DLCContentPanel%.") then
        local menu_path = current:match("^(.-WBP_MainMenu_C_%d+)")
        local panel = resolve(current:match("^(.-%.DLCContentPanel)"))
        print("[VoyagerAccess] back: closing the DLC panel\n")
        if panel and panel.CloseButton and panel.CloseButton:IsValid() then click(panel.CloseButton) end
        ExecuteInGameThreadWithDelay(300, function()
            pcall(function()
                if current and not current:find("%.DLCContentPanel%.") and resolve(current) then return end
                local b = nil
                for _, x in ipairs(FindAllOf("CommonButtonBase") or {}) do
                    local p = x:IsValid() and live(x) and path_of(x)
                    if p and menu_path and p:sub(1, #menu_path) == menu_path and p:find("%.DLCButton$") then b = x end
                end
                if b then b:SetFocus() end
            end)
        end)
        return
    end
    speech.say("Nothing to go back to", true)
end

-- Left/Right on a settings row: the game only wires these to the mouse
-- (the row's arrow buttons) and gamepad, so the mod calls the game's own
-- ChangeValueFromInput and speaks the new value.
local function adjust(left)
    crumb.at("key: left/right")
    if require("difficulty").adjust(current, left) then return end
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
    if require("dialogue").choice_edge(current, last) then return end
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
function M.current_path()
    return current
end

function M.current_label()
    -- A window's mod button list (no real focus): its current item.
    if virtual then
        local vb = resolve(virtual.buttons[virtual.index])
        local ok, l = pcall(label_for, vb, virtual.buttons[virtual.index])
        if ok and l then
            if l:find("%d+ of %d+") then return l end
            return string.format("%s, %d of %d", (l:gsub("%.$", "")), virtual.index, #virtual.buttons)
        end
    end
    local b = resolve(current)
    if not (b and require("screen").shown(b)) then return nil end
    if radial_said[current] then return radial_said[current] end
    local ok, label = pcall(label_for, b, current)
    return ok and with_position(label, current) or nil
end

-- "settings" or "menu" when an on-screen button has focus, else nil.
function M.context()
    local b = resolve(current)
    -- Before the on-screen check: the Q Trials pickers count as hidden.
    if b and require("qtrials").handles(current) then return "qtrials" end
    if b and require("difficulty").handles(current) then return "difficulty" end
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
        go_in_until = ticks + 30   -- a panel animates open first
        if require("popups").close_tutorial() then return end
        if require("whatsnew").open() then return require("whatsnew").close() end
        if require("hotkeys").open() then return require("hotkeys").repeat_item() end
        if require("credits").open() then return require("credits").repeat_item() end
        if require("techtree").open() then return require("techtree").enter() end
        if ship.list_open() then return ship.list_enter() end
        if require("resources").list_open() then return require("resources").close() end
        if require("view").nav_open() then return require("view").nav_enter() end
        if away.keys_active() then return away.mission_enter() end
        if M.virtual_active() then return M.virtual_enter() end
        -- In battle with no wheel open, Enter opens Orders (combat.lua).
        -- Not while focus is in the battle setup (HeroLoadout): Enter on Auto
        -- Resolve opened Orders there, and that started the battle by hand.
        -- The setup counted as not shown at that moment (Casey's machine,
        -- 2026-10-15, Vidiian ambush).
        if require("combat").active() and not (current and current:find(".HeroLoadout.", 1, true)) then
            local fb = resolve(current)
            if not (fb and require("screen").shown(fb)) then return require("combat").open_orders() end
        end
        if ship_mode() then return ship.open() end
        if map_mode() then return system.enter() end
        activate()
    end)
    keys.on("backspace", function()
        go_in_until = ticks + 5
        if require("whatsnew").close() then return end
        if require("hotkeys").close() then return end
        if require("credits").close() then return end
        if ship.list_close() then return end
        if require("resources").close() then return end
        if require("view").nav_close() then return end
        if map_mode() and system.menu_close() then return end
        go_back()
    end)
    -- Escape is the game's (the pause menu, closing windows), but it also
    -- closes the mod's own lists: with C open, Escape opened the pause menu
    -- and the C list kept the arrow keys (2026-10-14).
    -- The same Escape opens the game's pause menu, which the player did not
    -- ask for (the next keys went into Settings, 2026-10-14): when Escape
    -- closed a mod list, a pause menu that opens right after is resumed.
    local function undo_pause()
        M.undo_pause_until = os.clock() + 1.5
        local tries = 0
        local function check()
            tries = tries + 1
            for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
                if b:IsValid() and b:GetFName():ToString() == "ResumeButton" and live(b)
                    and b:GetFullName():find("WBP_PauseMenu_C", 1, true) and require("screen").shown(b) then
                    print("[VoyagerAccess] escape: closing the pause menu it opened\n")
                    click(b)
                    return
                end
            end
            if tries < 5 then ExecuteInGameThreadWithDelay(100, function() pcall(check) end) end
        end
        ExecuteInGameThreadWithDelay(100, function() pcall(check) end)
    end
    keys.on("escape", function()
        go_in_until = ticks + 5
        local closed = require("whatsnew").close() or require("hotkeys").close() or ship.list_close() or require("resources").close()
            or require("view").nav_close() or (map_mode() and system.menu_close())
        if closed then undo_pause() end
    end)
    -- Lists move with Up and Down everywhere (Casey, 2026-10-10); Left and
    -- Right change values. Page Up and Down change deck in the ship view.
    keys.on("up", function()
        pcall(require("combat").energy_key)
        if require("qtrials").step(current, -1) then return end
        if require("rooms").trade_offer_step(current, -1) then return end
        if require("whatsnew").open() then require("whatsnew").step(-1)
        elseif require("hotkeys").open() then require("hotkeys").step(-1)
        elseif require("credits").open() then require("credits").step(-1)
        elseif require("techtree").open() then require("techtree").step(-1)
        elseif ship.list_open() then ship.list_step(-1)
        elseif require("resources").list_open() then require("resources").step(-1)
        elseif require("view").nav_open() then require("view").nav_step(-1)
        elseif away.keys_active() then away.mission_step(-1)
        elseif require("view").heroes_open() then require("view").hero_step(-1)
        elseif M.virtual_active() then M.virtual_step(-1)
        elseif require("warpcore").handles(current) then require("warpcore").move(current, 1)
        elseif require("dialogue").choice_step(current, -1) then last_dir = -1 arrow_tick = ticks
        elseif ship_mode() then ship.deck(-1)
        elseif map_mode() then if system.menu_open() then system.menu_step(-1) else system.step(-1) end
        else last_dir = -1 arrow_tick = ticks end
    end)
    keys.on("down", function()
        pcall(require("combat").energy_key)
        if require("qtrials").step(current, 1) then return end
        if require("rooms").trade_offer_step(current, 1) then return end
        if require("whatsnew").open() then require("whatsnew").step(1)
        elseif require("hotkeys").open() then require("hotkeys").step(1)
        elseif require("credits").open() then require("credits").step(1)
        elseif require("techtree").open() then require("techtree").step(1)
        elseif ship.list_open() then ship.list_step(1)
        elseif require("resources").list_open() then require("resources").step(1)
        elseif require("view").nav_open() then require("view").nav_step(1)
        elseif away.keys_active() then away.mission_step(1)
        elseif require("view").heroes_open() then require("view").hero_step(1)
        elseif M.virtual_active() then M.virtual_step(1)
        elseif require("warpcore").handles(current) then require("warpcore").move(current, -1)
        elseif require("dialogue").choice_step(current, 1) then last_dir = 1 arrow_tick = ticks
        elseif ship_mode() then ship.deck(1)
        elseif map_mode() then if system.menu_open() then system.menu_step(1) else system.step(1) end
        else last_dir = 1 arrow_tick = ticks end
    end)
    local rooms = require("rooms")
    keys.on("left", function()
        pcall(require("combat").energy_key)
        go_in_until = ticks + 5
        if require("qtrials").switch_ship(current, -1) then return end
        if require("events").hero_step(current, -1) then return end
        if require("techtree").open() then return require("techtree").switch_tab(-1) end
        if require("popups").log_tab(-1) then return end
        if require("view").overview_tab(-1) then return end
        if rooms.window_open() then rooms.switch_tab(-1)
        elseif ship_mode() then ship.step(-1) elseif not map_mode() then adjust(true) end
    end)
    keys.on("right", function()
        pcall(require("combat").energy_key)
        go_in_until = ticks + 5
        if require("qtrials").switch_ship(current, 1) then return end
        if require("events").hero_step(current, 1) then return end
        if require("techtree").open() then return require("techtree").switch_tab(1) end
        if require("popups").log_tab(1) then return end
        if require("view").overview_tab(1) then return end
        if rooms.window_open() then rooms.switch_tab(1)
        elseif ship_mode() then ship.step(1) elseif not map_mode() then adjust(false) end
    end)
    keys.on("j", function()
        if ship.list_open() or ship_mode() then ship.list_toggle()
        else speech.say("J lists the rooms in the ship view", true) end
    end)
    keys.on("pageup", function() if ship_mode() then ship.deck(-1) end end)
    keys.on("pagedown", function() if ship_mode() then ship.deck(1) end end)
    local function home_end(last)
        if require("whatsnew").open() then return require("whatsnew").edge(last) end
        if require("hotkeys").open() then return require("hotkeys").edge(last) end
        if require("credits").open() then return require("credits").edge(last) end
        if require("techtree").open() then return require("techtree").edge(last) end
        if ship.list_open() then return ship.list_edge(last) end
        if require("resources").list_open() then return require("resources").edge(last) end
        if require("view").nav_open() then return require("view").nav_edge(last) end
        if away.keys_active() then return away.mission_edge(last) end
        if require("view").heroes_open() then return require("view").hero_step(last and 1 or -1, true) end
        if M.virtual_active() then return M.virtual_edge(last) end
        if ship_mode() then return ship.edge(last) end
        if require("difficulty").edge(current, last) then return end
        if require("qtrials").edge(current, last) then return end
        if away.loadout_edge(current, last) then return end
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
