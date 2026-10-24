-- Speaks the focused button whenever keyboard/gamepad focus moves.
-- Proven 2026-10-10 on the main menu: arrow keys move Slate focus to a widget
-- INSIDE a CommonButtonBase, and CommonButtonBase:HandleFocusReceived never
-- fires, so focus has to be looked up (HasFocusedDescendants or
-- HasKeyboardFocus on buttons).
--
-- When: once after anything that can move focus, never on a timer. The
-- 100 ms loop held the game long enough to swallow keys (E on the Mess
-- Hall: 14 of 56 lost with the mod's loops running, 36 of 36 with them
-- stopped; firefly82, 2026-10-21). What moves focus is the player's input
-- (keys.lua tells after every key and mouse button, the game's own too) and
-- the game opening or closing a window or showing choices (popups.lua and
-- dialogue.lua ask for a look then): M.request_check.

local speech = require("speech")

local M = {}

-- Never keep a UObject across ticks: the game destroys widgets (menus close,
-- dialogue ends) and touching the stale object crashed UE4SS while wrapping
-- a garbage pointer (symbolized crash, 2026-10-10 21:55). Keep paths and
-- look them up again with resolve() each time.
local current = nil          -- path of the focused button
-- The last of the mod's keys that moves in or between menus, so a focus
-- change is put down to the key that caused it, not to a time window:
-- "arrow" (Up, Down) or "go_in" (Enter, Left, Right, Backspace, Escape).
-- The 100 ms loop used "within 2 polls of an arrow" and "30 polls after
-- Enter" instead (firefly82's review, 2026-10-21).
local last_nav = nil
-- The dialogue choice whose label was said last; Enter picks only a choice
-- the player has heard (it used to be "not within 10 polls of the choices
-- appearing").
local heard_choice = nil
-- The focused choice was seen hidden since it was last said: when it is
-- shown again, it is said again (was "not seen for 0.6 s").
local choice_hidden = false
-- Paths of buttons Enter was pressed on, oldest first; Backspace returns to them.
local back_stack = {}
local pending_click = nil    -- { button = path, menu = path }
local click
local label_for
local confirm_order
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

-- The same label from the button's own widget tree: searching all 5,000
-- texts in the game took about 30 ms on every focus change (probe in the
-- VM, 2026-10-21); the button's tree has a handful. TextBlocks and their
-- subclasses count (FindAllOf("TextBlock") returned the CommonTextBlocks
-- too, probe 2026-10-21); rich text never did.
local function label_from_tree(path)
    local root = StaticFindObject(path)
    if not (root and root:IsValid()) then return nil end
    local T = StaticFindObject("/Script/UMG.TextBlock")
    local screen = require("screen")
    if not screen.shown(root) then return nil end
    local parts, seen = {}, {}
    -- Visibility followed on the way down (screen.walk), not climbed for
    -- each text; no list entries, as the search found none inside buttons.
    -- Only texts whose path is under the button, as the search had it: a
    -- text the game made at run time inside the button belongs to the game
    -- instance (Fable review, 2026-10-21).
    local prefix = path .. "."
    screen.walk(root, function(w)
        if not (T and w:IsA(T)) then return false end
        local wp = w:GetFullName():match("^%S+%s+(.+)$")
        if wp and wp:sub(1, #prefix) == prefix and w:GetFName():ToString() ~= "Entitlement_TXT" then
            local ok, s = pcall(function() return w:GetText():ToString() end)
            if ok and s ~= "" and s:sub(1, 1) ~= "#" and not seen[s] then
                seen[s] = true
                parts[#parts + 1] = s
            end
        end
        return true
    end, { limit = 300, no_lists = true })
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Development only (flag file "treecheck"): both labels, compared and
-- timed; a difference is logged once.
local TREECHECK = (function()
    local f = io.open((os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\treecheck", "r")
    if f then f:close() return true end
    return false
end)()
do
    local search = label_of
    local logged = {}
    label_of = function(path)
        local t0 = os.clock()
        local tree = label_from_tree(path)
        if not TREECHECK then return tree end
        local t1 = os.clock()
        local old = search(path)
        local t2 = os.clock()
        if old ~= tree then
            local key = tostring(old) .. "|" .. tostring(tree)
            if not logged[key] then
                logged[key] = true
                print(string.format("[VoyagerAccess] treecheck: label DIFFERS search [%s] %d ms tree [%s] %d ms | %s\n",
                    tostring(old), math.floor((t2 - t1) * 1000 + 0.5), tostring(tree),
                    math.floor((t1 - t0) * 1000 + 0.5), path))
            end
        elseif not logged.same then
            logged.same = true
            print(string.format("[VoyagerAccess] treecheck: label same, search %d ms tree %d ms\n",
                math.floor((t2 - t1) * 1000 + 0.5), math.floor((t1 - t0) * 1000 + 0.5)))
        end
        return tree
    end
end

-- Live widgets sit under /Engine/Transient; FindAllOf also returns blueprint
-- templates under /Game/..., which have no Slate widget behind them. Skip
-- those (an access violation inside UE4SS followed touching them, 2026-10-10).
local function live(obj)
    local path = path_of(obj)
    return path ~= nil and path:sub(1, 18) == "/Engine/Transient."
end
M.live = live

-- The dialogue choice Enter last picked (a hold choice), and its label then.
-- The game reuses a choice widget for the next choice, so a match on the
-- widget alone held "Fire" for "already picked" and Enter never fired the
-- tricobalt devices (forum report, 0.3.50, 2026-10-18).
local picked_choice, picked_label = nil, nil

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
    -- The game's own name for the segment, in its language ("Trümmer
    -- beseitigen", "Logistik"; firefly82's review, 2026-10-20). The asset
    -- name below is the fallback for a command with none (the pause ring).
    local okn, own = pcall(function()
        local c = b.Command
        if not (c and c:IsValid()) then return nil end
        return c.CommandName:ToString()
    end)
    if okn and type(own) == "string" and own ~= "" then
        local lockedn = false
        pcall(function() lockedn = require("screen").shown(b.LockImage) end)
        return lockedn and (own .. ", locked") or own
    end
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
local last_center_error = nil   -- set by radial_details

-- The text widgets inside the ring's centre, in tree order. The centre is
-- the ring's own CenterWidget (hovered segment) or UnselectedCenterWidget:
-- a search over every text filtered by "WBP_RadialMenuCenter_" in the path
-- missed the ruin's WBP_UnselectedCenter_Ruin (firefly82's review,
-- 2026-10-20). nil when the ring has no centre reference.
local function center_texts(menu_path)
    local menu = resolve(menu_path)
    if not menu then return nil end
    local c = nil
    pcall(function()
        local w = menu.CenterWidget
        if w and w:IsValid() and require("screen").shown(w) then c = w; return end
        w = menu.UnselectedCenterWidget
        if w and w:IsValid() and require("screen").shown(w) then c = w end
    end)
    if not c then return nil end
    local W = StaticFindObject("/Script/UMG.UserWidget")
    local P = StaticFindObject("/Script/UMG.PanelWidget")
    local out, count = {}, 0
    local function walk(w, depth)
        if depth > 30 or count > 400 or not (w and w:IsValid()) then return end
        count = count + 1
        local okt = pcall(function() return w:GetText() end)
        if okt and not w:IsA(W) then out[#out + 1] = w; return end
        if w:IsA(W) then
            local tree = w.WidgetTree
            if tree and tree:IsValid() and tree.RootWidget then walk(tree.RootWidget, depth + 1) end
        elseif w:IsA(P) then
            for i = 0, w:GetChildrenCount() - 1 do walk(w:GetChildAt(i), depth + 1) end
        end
    end
    walk(c, 0)
    return out, path_of(c)
end

local function radial_details(menu)
    local by, order = {}, {}
    local center = nil
    -- Clear Debris shows what it gives back as "+16" in a DuraniumDisplay
    -- (WBP_RadialMenuCenter_ClearDebris, VM, 2026-10-15); every display's
    -- number is named AmountText, so the resource is the display's name.
    local gives, gave = {}, {}
    local texts, cpath = center_texts(menu)
    local lists = {}
    if texts then
        center = cpath
        lists[1] = texts
    else
        print("[VoyagerAccess] radial: no centre reference, searching\n")
        for _, cls in ipairs({ "TextBlock", "RichTextBlock", "CommonTextBlock", "CommonRichTextBlock" }) do
            lists[#lists + 1] = FindAllOf(cls) or {}
        end
    end
    for _, list in ipairs(lists) do
        for _, t in ipairs(list) do
            local tp = t:IsValid() and path_of(t)
            -- The centre is not inside the ring's path; any shown one counts.
            if tp and (texts or (tp:find("^/Engine/Transient%.") and tp:find("WBP_RadialMenuCenter_", 1, true)))
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
                        -- The game's own name in other languages (English
                        -- keeps the widget's name, as before).
                        local word = require("text").game_resource_name(res) or (res:gsub("(%l)(%u)", "%1 %2")):lower()
                        gives[#gives + 1] = (s:gsub("^%+", "")) .. " " .. word
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
    last_center_error = by.ErrorText
    if by.ErrorText then parts[#parts + 1] = by.ErrorText end
    if by.RoomDescriptionText then parts[#parts + 1] = by.RoomDescriptionText end
    if by.DescriptionText then parts[#parts + 1] = by.DescriptionText end
    if #gives > 0 then parts[#parts + 1] = "Gives " .. table.concat(gives, ", ") end
    local op = {}
    if by.EnergyValue then op[#op + 1] = "energy " .. by.EnergyValue end
    if by.CrewValue then op[#op + 1] = require("tr").fill("crew {s}", by.CrewValue) end
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
local ring_pending = nil  -- { path, fn }: the segment waiting for its hover
local ring_hooked = false
-- The ring focus last came into, until that ring closes (radial_focus).
local ring_entered = nil
pcall(function()
    require("popups").on_close(function(_, cls)
        if cls == "WBP_RadialMenu_C" then ring_entered = nil end
    end)
end)
-- segment path -> the ring centre's own error text (the game's words, in its
-- language), the reason a locked segment gives on Enter.
local radial_error = {}

-- Focus reached a segment: hover it with the mouse (through the helper),
-- say at once what the segment itself gives (a room's data, or the
-- command's name), and the centre's details once the game reports the
-- hover.
local install_ring_hover   -- below

function M.radial_focus(b, path)
    local menu = path:match("^(.-WBP_RadialMenu_C_%d+)%.")
    -- The segment's class is loaded now that focus is on one: hook its hover
    -- before the pointer moves (no 3 s install loop).
    pcall(install_ring_hover, b)
    -- A room to build is read from the game's data at once: the hover and
    -- its 450 ms wait matched the centre for none of 45 room segments in a
    -- two-hour session, so every arrow key waited for nothing (firefly82,
    -- German game, 2026-10-18). Other segments still hover for the centre.
    local okr0, ring0 = pcall(require("construction").ring_text, b)
    local direct = okr0 and ring0 ~= nil
    -- With the hover hook a room segment is pointed at too, so its lock
    -- reason is the centre's own (the game's words, in its language) and
    -- not one the mod works out (firefly82's review, 2026-10-20).
    if not direct or ring_hooked then
        pcall(function()
            local pos = b.Slot:GetPosition()
            local r = math.max(math.sqrt(pos.X * pos.X + pos.Y * pos.Y), 1)
            -- The ring point is the segment's inner edge; its middle is half
            -- the segment's height further out (Alignment 0.5/1.0). The
            -- helper puts the pointer at 350/1080 of the window height per
            -- unit, right only for 16:9: the UI scales by the viewport scale,
            -- so in 1024x768 the pointer missed every segment and no centre
            -- (and no locked reason) appeared (firefly82's review, German
            -- game, 2026-10-20). Convert to the helper's unit here, so older
            -- helpers point right too. Every number comes from the game (the
            -- segment's own size, the viewport's scale and size); without one
            -- of them the pointer stays where it is rather than going to a
            -- guessed place (the old fallback was a fixed 62).
            -- 350/1080 is the helper's own unit (speech.ring_mouse), not a
            -- game value.
            local k = nil
            pcall(function()
                local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
                local scale = wll:GetViewportScale(b)
                local size = wll:GetViewportSize(b)
                local d = b:GetDesiredSize()
                if type(scale) == "number" and scale > 0 and size and size.Y and size.Y > 0
                    and d and d.Y and d.Y > 0 then
                    k = (r + d.Y / 2) * scale / (350 / 1080 * size.Y)
                end
            end)
            if not k then
                print("[VoyagerAccess] radial: no segment size or viewport scale, pointer not moved\n")
                return
            end
            print(string.format("[VoyagerAccess] radial: pointer %.2f radii\n", k))
            speech.ring_mouse(k * pos.X / r, k * pos.Y / r)
        end)
    end
    -- hovered: the game has said this segment is under the pointer, so its
    -- centre is this segment's and may be read. Before that only what
    -- belongs to the segment itself is read (its name, a room's data): a
    -- centre read without the game's word may still show the segment the
    -- pointer was on before.
    local function say_it(hovered)
        pcall(function()
            if current ~= path then return end
            local nb = resolve(path)
            if not nb then return end
            local text = nil
            local reason_only = nil   -- the hover added just the game's reason
            local okr, ring = pcall(require("construction").ring_text, nb)
            if okr and ring then
                text = ring.text
                -- Before the hover, no reason of the mod's own when the game's
                -- will follow: every blocked choice was said twice with two
                -- reasons, "Technologie fehlt" (the mod's) then "Fehlende
                -- Technologie" (the centre's; firefly82's review, 2026-10-23).
                if not hovered and ring_hooked and ring.why and not ring.why:find("^Missing resources") then
                    text = text:gsub("%s*" .. ring.why:gsub("%p", "%%%0") .. "%.?", "", 1)
                end
                -- The centre's reason when it shows one. "Missing resources"
                -- keeps the mod's, which names the short ones (a sighted
                -- player sees those costs in red).
                if menu and hovered and not (ring.why and ring.why:find("^Missing resources")) then
                    last_center_error = nil
                    pcall(radial_details, menu)
                    local ge = last_center_error and last_center_error:gsub("%.%s*$", "")
                    if ge and ge ~= "" then
                        radial_error[path] = ge
                        -- The first reading left the mod's reason out, so the
                        -- hover adds only the game's, not the whole room again.
                        if ring.why and ring_hooked and radial_said[path] then reason_only = ge end
                        if ring.why then
                            text = text:gsub(ring.why:gsub("%p", "%%%0"), (ge:gsub("%%", "%%%%")), 1)
                        else
                            text = text:gsub("^([^%.]+)%.", "%1. " .. ge:gsub("%%", "%%%%") .. ".", 1)
                        end
                    end
                end
            elseif menu and hovered then
                last_center_error = nil
                text = radial_details(menu)
                radial_error[path] = last_center_error
            end
            if not text or text == "" then text = M.radial_label(nb) or "Button" end
            if text:find("^[^%.]+%. Missing resources%.") then
                local oks, short = pcall(require("construction").shortages, nb)
                if oks and short then
                    text = text:gsub("Missing resources%.", "Missing resources: " .. short:gsub("%%", "%%%%") .. ".", 1)
                end
            end
            -- A room to build: its width and whether it fits at the selected
            -- space (construction.lua).
            local okf, fit = pcall(require("construction").fit_text, nb)
            if okf and fit then text = text:gsub("%.%s*$", "") .. ". " .. fit end
            local place = ring_place(nb)
            if place ~= "" then text = text .. ". " .. place end
            -- The hover's reading only when it adds something: a room whose
            -- centre gave no other reason is not said twice.
            if hovered and radial_said[path] == text then return end
            radial_said[path] = text
            print("[VoyagerAccess] radial: " .. (hovered and "hovered: " or "") .. text .. "\n")
            if reason_only then
                speech.say(reason_only, false)
                return
            end
            speech.say(text, true)
        end)
    end
    -- At once what the segment itself gives (no waiting); then again, with
    -- its centre, when the game says the segment is hovered (BP_OnHovered,
    -- install_ring_hover). There is no timer: a pointer that missed the
    -- segment leaves the first reading standing, and the log says so when
    -- focus moves on (firefly82's review, 2026-10-21; the fixed 450 ms and
    -- then the 1000 ms fallback read a centre that could still be another
    -- segment's).
    if ring_pending and ring_pending.fn then
        print("[VoyagerAccess] radial: no hover came for " .. ring_pending.path:match("([^%.]+)$") .. "\n")
    end
    ring_pending = nil
    -- As the ring opens, its own text (popups.lua) is not read yet: the
    -- segment's name came first, then the ring's text, then the segment
    -- again with its centre ("Clear Debris. 1 of 1. Ruined Room. You can use
    -- a work team... Clear Debris. No Life Support...", VM, 2026-10-21).
    -- Then only the hovered reading is said, after the ring's text; if the
    -- game reports no hover, the segment's own reading comes after 700 ms.
    -- Opening: focus has just come into this ring (the game reuses the ring
    -- widget, so a reopened ring is the same path; ring_entered is cleared
    -- when the ring closes).
    local opening = ring_hooked and menu and ring_entered ~= menu
    ring_entered = menu
    -- Opening says the hovered reading whole: an older reading of this
    -- segment must not make it just the reason.
    if opening then radial_said[path] = nil end
    if not opening then say_it(false) end
    if ring_hooked then ring_pending = { path = path, fn = function() say_it(true) end } end
    if opening then
        local mine = ring_pending
        -- The hover stays pending: if it comes later, its centre is still
        -- said (say_it skips a hovered reading that adds nothing; GPT
        -- review, 2026-10-21).
        ExecuteInGameThreadWithDelay(700, function()
            if ring_pending == mine and mine.fn then
                print("[VoyagerAccess] radial: no hover as the ring opened, read without its centre\n")
                say_it(false)
            end
        end)
    end
end

-- The segment's own hover event: a pre callback, so the centre is read on
-- the next tick, after the game has filled it. BP_OnHovered is CommonUI's
-- event, which every segment class implements for itself
-- (WBP_RadialButton_C and the six WBP_RadialButtonCombat*_C, CXX dump
-- 2026-10-18; WBP_RadialButton_Small_C uses its parent's), so the hook goes
-- on the class that defines it for this segment, found from the segment
-- itself when focus first reaches one of its kind.
local ring_hooked_on = {}   -- function path -> true once hooked

local function on_ring_hover(ctx)
    local okp, bp = pcall(function() return path_of(ctx:get()) end)
    if not okp then return end
    ExecuteInGameThread(function()
        local p = ring_pending
        if p and p.fn and p.path == bp then
            print("[VoyagerAccess] radial: hovered\n")
            local fn = p.fn; p.fn = nil; fn()
        end
    end)
end

install_ring_hover = function(b)
    ring_hooked = false
    local cls = b and b:GetClass()
    while cls and cls:IsValid() do
        local fpath = cls:GetFullName():match("^%S+%s+(.+)$") .. ":BP_OnHovered"
        if ring_hooked_on[fpath] then ring_hooked = true; return end
        if StaticFindObject(fpath) then
            local ok = pcall(RegisterHook, fpath, on_ring_hover)
            ring_hooked_on[fpath] = ok or nil
            ring_hooked = ok
            print("[VoyagerAccess] radial: hover hook on " .. fpath:match("([%w_]+:BP_OnHovered)$") .. (ok and " installed" or " not installed") .. "\n")
            return
        end
        cls = cls:GetSuperStruct()
    end
    print("[VoyagerAccess] radial: no BP_OnHovered for this segment's class\n")
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

-- Visibility is followed on the way down (screen.walk): M.shown on every
-- widget, climbing to the top each time, made finding a window's buttons
-- hold the game for up to 250 ms (timing log, VM, 2026-10-21).
local function buttons_in(w, out)
    local screen = require("screen")
    if not (w and w:IsValid() and screen.shown(w)) then return end
    screen.walk(w, function(x)
        if x:IsA(BUTTON_CLASS) then
            if x:GetIsEnabled() then out[#out + 1] = x end
            return true
        end
        return false
    -- wire_rows walks from the top of the screen; the old walk had no
    -- count limit, so this one is high (and logged if reached).
    end, { no_lists = true, limit = 20000 })
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
-- A window's button list ends with the window: kept until the next look
-- (after a key), it made help.lua count the closed Overview as still in
-- front, and the view was not said (GPT review, 2026-10-21).
pcall(function()
    require("popups").on_close(function(p)
        if virtual and virtual.window == p then virtual = nil end
    end)
end)

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
    -- The unassigned slots warning is answered from the window list; putting
    -- focus back on "start mission" behind it took the arrows away (VM,
    -- 2026-10-18).
    local okw, warn = pcall(function() return require("combat").fewer_heroes_open() end)
    if okw and warn then return false end
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
                -- Never the HUD's invisible back button: with focus there, the
                -- game's own Enter closed No Way Back as a NO before the
                -- mod's click on YES (2 of 6 tries, VM, 2026-10-18).
                if op and op:sub(1, #prefix + 1) == prefix .. "." and require("screen").shown(o)
                    and not op:find("InvisBackButton", 1, true) then near = o break end
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
    -- By class too: the Cargo Bay's warning is a member named
    -- ResourceCapacityChangeConfirmWidget, so its path never names its
    -- class, and a notice behind it took the arrows (VM, 2026-10-16).
    local ok, cls = pcall(function()
        local o = StaticFindObject(p)
        return o and o:IsValid() and o:GetClass():GetFName():ToString() or ""
    end)
    if ok and cls ~= "" then
        for _, c in ipairs(CONFIRMS) do if cls == c then return true end end
    end
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
-- The pause menu's Gamma window over a conversation: its buttons may never
-- take focus (SetFocus on CONFIRM did nothing), the dialogue rule kept the
-- button list away, the arrows were silent, and Enter went on with the
-- conversation behind it (demo, Caretaker's ending, VM, 2026-10-22).
-- Asked on every focus look, so the answer is kept for 300 ms (a FindAllOf
-- each time was a steady cost; Fable review, 2026-10-22).
local gamma_at, gamma_was = -100, false
local function gamma_open()
    if os.clock() - gamma_at < 0.3 then return gamma_was end
    gamma_at, gamma_was = os.clock(), false
    for _, w in ipairs(FindAllOf("WBP_GammaCorrection_C") or {}) do
        if w:IsValid() and live(w) and require("screen").shown(w) then gamma_was = true break end
    end
    return gamma_was
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
    if require("dialogue").active() and not pause_confirm_open() and not gamma_open() then
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
    -- The away team setup's "unassigned slots" warning is a part of the
    -- setup, not a window of its own: its Return and Continue were listed
    -- with the slots and Start behind it ("Return, 5 of 6", and Up went to
    -- start mission; VM, 2026-10-22). combat.lua finds it in any setup.
    if not modal then
        local okf, fp = pcall(function() return require("combat").fewer_heroes_path() end)
        if okf and fp then modal = fp end
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
    if virtual and require("dialogue").active() and not is_confirm(virtual.window)
        and not virtual.window:find("WBP_GammaCorrection_C", 1, true) then virtual = nil end
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

-- An order in battle: the wheel closed and nothing was said, so Repair
-- Warp Core seemed not to take (VM, 2026-10-17). Once the wheel has gone
-- (a submenu such as Initiate Repairs keeps it open), say the order. The
-- repair segments are WBP_RadialButtonCombatRepair and are pressed through
-- the window button list.
local ORDER_CLASSES = { WBP_RadialButtonCombatOffensive_C = true, WBP_RadialButtonCombatRepair_C = true,
    WBP_RadialButton_C = true }
confirm_order = function(b, path, said)
    pcall(function()
        local cls = b:GetClass():GetFName():ToString()
        if not (ORDER_CLASSES[cls] and require("combat").active()) then return end
        said = said or radial_said[path]
        if not said and require("combat").handles(b, path) then said = require("combat").button_label(b, path) end
        if not said then said = label_for(b, path) end
        local name = said and said:match("^([^,%.]+)")
        if not name or name:find("^Back") then return end
        ExecuteInGameThreadWithDelay(900, function()
            pcall(function()
                for _, m in ipairs(FindAllOf("WBP_RadialMenu_C") or {}) do
                    if m:IsValid() and path_of(m):find("^/Engine/Transient%.") and require("screen").shown(m) then return end
                end
                -- An offensive segment is the enemy system to aim at: "Warp
                -- Core ordered" read oddly (VM, 2026-10-17).
                speech.say(cls == "WBP_RadialButtonCombatOffensive_C" and ("Targeting " .. name) or (name .. " ordered"), false)
            end)
        end)
    end)
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
    local bpath = virtual.buttons[virtual.index]
    local okb, before = pcall(label_for, b, bpath)
    confirm_order(b, bpath, okb and before or nil)
    -- ACCEPT on Exit to Main Menu: focus goes back to the pause menu's
    -- RESUME while the game unloads, and "RESUME, 1 of 5" was said before
    -- the main menu (VM, 2026-10-21). The pause menu is not said meanwhile.
    if bpath:find(PAUSE_CONFIRM, 1, true) and bpath:find("%.AcceptButton$")
        and last_real and last_real:find("WBP_PauseMenu_C", 1, true) and last_real:find("%.MainMenuButton$") then
        M.undo_pause_until = os.clock() + 5
    end
    click(b)
    -- Some windows close with no event the mod can hook (an info card's
    -- Close: no CloseInfoWidget, OnCloseClicked or CallOnCloseEvent came,
    -- VM, 2026-10-21): popups reads their state. It is final as the click
    -- returns (IsActivated false in the same call, probe 2026-10-22), so
    -- now, not 350 ms later.
    pcall(function() require("popups").check_gone() end)
    -- A button whose wording changes said nothing: the Engineering
    -- Office's "Unassign from hull repair" became "Assign to hull repair"
    -- silently, its row rebuilt with new object numbers (VM, 2026-10-16).
    -- Said again once changed, found by its path without the numbers.
    ExecuteInGameThreadWithDelay(400, function()
        pcall(function()
            local nb, np = resolve(bpath), bpath
            if not (nb and require("screen").shown(nb)) then
                nb = nil
                local key = bpath:gsub("_%d+", "")
                for _, o in ipairs(FindAllOf("CommonButtonBase") or {}) do
                    local op = o:IsValid() and live(o) and path_of(o)
                    if op and op:gsub("_%d+", "") == key and require("screen").shown(o) then nb, np = o, op break end
                end
            end
            if not nb then return end
            local after = label_for(nb, np)
            if okb and after and after ~= before then
                print("[VoyagerAccess] changed: " .. after .. "\n")
                speech.say(after, true)
            end
        end)
    end)
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
local groups = {}      -- button path -> the paths counted with it, in order
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
        -- Nor Settings headings, spacer rows and settings that cannot be
        -- changed (Display Resolution in windowed fullscreen): Graphics
        -- counted 18 rows and never reached 7, 8, 13 or 14 (demo, VM,
        -- 2026-10-16).
        pcall(function()
            if b:GetClass():GetFName():ToString() == "WBP_Setting_C"
                and (is_heading(b) or not is_setting(b) or not b:GetIsEnabled()) then status = true end
        end)
        if require("screen").shown(b) and not status then
            list[#list + 1] = b
            names[#names + 1] = all_names[i]
        else
            positions[all_names[i]] = nil
            groups[all_names[i]] = nil
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
    local function tab(n) return n:find("TabButton$") ~= nil end
    -- The buttons under panel a that count with button i.
    local function group_at(i, a)
        -- An event's CONTINUE was counted with the HUD's own buttons
        -- ("CONTINUE, 16 of 16", VM, 2026-10-15): a button that is not the
        -- HUD's does not count the HUD's.
        local in_hud = names[i]:find("WBP_HUD_C_", 1, true) ~= nil
        -- Nor a room's tab bar: a damaged Aeroshuttle Bay's only action was
        -- "Repair, 6 of 6" with the five tab buttons (VM, 2026-10-15).
        local is_tab = tab(names[i])
        local group = {}
        for j = 1, #list do
            if chains[j].set[a] and (in_hud or not names[j]:find("WBP_HUD_C_", 1, true))
                and (is_tab or not tab(names[j])) then
                group[#group + 1] = j
            end
        end
        return group
    end
    -- Each button's nearest panel holding two or more counted buttons.
    local near = {}
    for i = 1, #list do
        for _, a in ipairs(chains[i].chain) do
            if #group_at(i, a) >= 2 then near[i] = a break end
        end
    end
    for i = 1, #list do
        positions[names[i]] = nil
        groups[names[i]] = nil
        for k, a in ipairs(chains[i].chain) do
            local group = group_at(i, a)
            -- A list in its own box with lone buttons beside it in the panel
            -- above (the first-launch graphics options "of 4" and CONFIRM
            -- "5 of 5", while Down goes through all five; VM, 2026-10-16):
            -- counted as one list. Only when every extra button is alone
            -- there, and not side by side (HorizontalBox, see below).
            -- The first panel above that holds more buttons than the list's
            -- own box (the graphics options sit two boxes below CONFIRM's).
            local a2, group2 = nil, nil
            if #group >= 2 then
                for m = k + 1, math.min(#chains[i].chain, k + 6) do
                    local g = group_at(i, chains[i].chain[m])
                    if #g > #group then a2, group2 = chains[i].chain[m], g break end
                end
            end
            if a2 then
                local inner = {}
                for _, j in ipairs(group) do inner[j] = true end
                local extra, lone = 0, true
                for _, j in ipairs(group2) do
                    if not inner[j] then
                        extra = extra + 1
                        if near[j] ~= a2 then lone = false end
                    end
                end
                local cls2 = "?"
                -- Valid first: GetClass on a null object crashed the game
                -- (help.lua's front_window, VM, 2026-10-16).
                pcall(function()
                    local o = StaticFindObject(a2)
                    if o and o:IsValid() then cls2 = o:GetClass():GetFName():ToString() end
                end)
                if extra > 0 and lone and cls2 ~= "HorizontalBox" and #group2 <= 40 then
                    group, a = group2, a2
                end
            end
            if #group >= 2 then
                -- Side-by-side columns (the main menu, its profiles and the
                -- save window in one HorizontalBox) are not one list: "NEW
                -- CAMPAIGN, 11 of 11". When another column has several
                -- buttons, a button alone in its column gets no count.
                local columns = false
                local cls = "?"
                pcall(function()
                    local o = StaticFindObject(a)
                    if o and o:IsValid() then cls = o:GetClass():GetFName():ToString() end
                end)
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
                    -- The counted list, for Home and End (edge).
                    local members = {}
                    for _, j in ipairs(group) do members[#members + 1] = names[j] end
                    groups[names[i]] = members
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
    -- Nor in a label all in capitals: "AUTOM. SPEICHERSTAND LADEN" (German
    -- "Load Autosave") was said "AUTOM, 2 of 4. SPEICHERSTAND LADEN"
    -- (firefly82, 2026-10-18); such a label has no sentences.
    if head and rest and not head:match("%f[%a]%u%l?%l?$") and label:find("%l") then
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
        -- Not disabled buttons: a Q Trials ambush disables Surrender and
        -- Use Cloak, Down from the last slot went onto Surrender, and focus
        -- could not leave it (VM, 2026-10-16).
        -- Nor the Science Laboratory's Analysis button with no analysis
        -- running: not focusable, counted ("1 of 2"), and Down never reached
        -- it (VM, 2026-10-17). Only there: the room's Dismantle and Upgrade
        -- also say not focusable, and focus does reach them.
        local enabled = true
        pcall(function()
            enabled = b:GetIsEnabled()
            if enabled and path_of(b):find("WBP_ScienceLab_ResearchModule_C", 1, true) then enabled = b:GetIsFocusable() end
            -- Nor the main menu panels' mouse-only BACK (WBP_ActionBar_BackButton_C,
            -- bIsFocusable false; Escape is its key): the DLC panel's six
            -- tiles were "1 of 7", Down never reached 7, and End went to
            -- the first tile (VM, 2026-10-22).
            if enabled and b:GetClass():GetFName():ToString() == "WBP_ActionBar_BackButton_C" and b.bIsFocusable == false then
                enabled = false
            end
        end)
        if enabled and not require("warpcore").handles(path_of(b)) then list[#list + 1] = b end
    end
    -- Focus on a disabled button moves on to the next usable one the way
    -- the player was going.
    pcall(function()
        local cur = resolve(path)
        if not (cur and cur:IsValid()) or cur:GetIsEnabled() then return end
        -- Only when an arrow moved it there: Auto Resolve disables its own
        -- button as its window opens, and focus was sent off somewhere
        -- hidden (VM, 2026-10-16).
        if last_nav ~= "arrow" then return end
        local at = nil
        for i, b in ipairs(all) do if path_of(b) == path then at = i end end
        if not at then return end
        local dir = (last_dir == -1) and -1 or 1
        local i = at + dir
        while all[i] do
            local okn, en = pcall(function() return all[i]:GetIsEnabled() and require("screen").shown(all[i]) end)
            if okn and en then
                print("[VoyagerAccess] focus: off disabled " .. path:match("([^%.]+)$") .. "\n")
                all[i]:SetFocus()
                return
            end
            i = i + dir
        end
    end)
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
        -- Up and Down stay in the call list, as on the room ring: the
        -- game's own Down left it for a hidden room's Repair button
        -- ("Menu. Repair, 26 of 26"), and N was refused after (PC,
        -- 2026-10-18).
        pcall(function()
            local list = {}
            for _, c in ipairs(FindAllOf("WBP_IncomingCall_List_Button_C") or {}) do
                if c:IsValid() and live(c) and require("screen").shown(c) then list[#list + 1] = c end
            end
            table.sort(list, function(x, y) return x:GetParent():GetChildIndex(x) < y:GetParent():GetChildIndex(y) end)
            for i = 1, #list do
                if list[i - 1] then list[i]:SetNavigationRuleExplicit(2, list[i - 1]) else list[i]:SetNavigationRuleBase(2, 3) end
                if list[i + 1] then list[i]:SetNavigationRuleExplicit(3, list[i + 1]) else list[i]:SetNavigationRuleBase(3, 3) end
                if path_of(list[i]) == path then label = label .. ", " .. i .. " of " .. #list end
            end
        end)
    elseif cls == "WBP_BioLab_Production_ItemDisplay_C" then
        label = require("rooms").biolab_item_label(b)
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
    elseif cls == "WBP_Resource_C" then
        -- A resource readout used as a button (the Q Trials sector results
        -- list ten of them): "0000, 0, +255, -24" (VM, 2026-10-16). Its
        -- widget is named after the resource; say "Deuterium 1,000".
        local key = path:match("([%w_]+)$") or ""
        local NAMES = { SciencePoints = "Science points", BioNeuralGelPack = "Bio-neural gel packs", BorgNanites = "Borg nanites" }
        local okv, v = pcall(function() return b.CurrentResourceAmountText:GetText():ToString() end)
        v = okv and v and v:gsub("^0+(%d)", "%1") or ""
        label = (NAMES[key] or key) .. (v ~= "" and (" " .. v) or "")
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
        -- All four are disabled while the bay is off (no life support, VM,
        -- 2026-10-16), and the arrows cannot reach the others then.
        local oke, en = pcall(function() return b:GetIsEnabled() end)
        if label and oke and en == false then label = label .. ". Choices locked while the cargo bay is off" end
        -- The four choices are a 2 by 2 grid: Down from the bottom row went
        -- nowhere and Right switches the window's tab, so Tritanium could
        -- not be reached (Q Trial, VM, 2026-10-16). Up and Down go through
        -- them all in order (EUINavigation Up 2, Down 3; rule Stop 3).
        pcall(function()
            local parent = b:GetParent()
            local list = {}
            for i = 0, parent:GetChildrenCount() - 1 do
                local c = parent:GetChildAt(i)
                if c and c:IsValid() and c:GetClass():GetFName():ToString() == "WBP_ResourceSelectionButton_C"
                    and require("screen").shown(c) then list[#list + 1] = c end
            end
            for i, c in ipairs(list) do
                if list[i - 1] then c:SetNavigationRuleExplicit(2, list[i - 1]) else c:SetNavigationRuleBase(2, 3) end
                if list[i + 1] then c:SetNavigationRuleExplicit(3, list[i + 1]) else c:SetNavigationRuleBase(3, 3) end
            end
        end)
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
    elseif b:GetClass():GetFName():ToString() == "WBP_CombatAllyButton_C"
        or b:GetClass():GetFName():ToString() == "WBP_CombatAllyRecruitedButton_C" then
        label = require("rooms").ally_label(b)
    elseif b:GetClass():GetFName():ToString() == "WBP_HUD_CyclesDisplay_C" then
        -- The HUD's cycle counter took the game's focus during an Overview
        -- tab switch and was read as a bare "24" (VM, 2026-10-17).
        local ok, n = pcall(function() return b.CyclesAmount:GetText():ToString() end)
        label = "Cycle counter" .. ((ok and n and n ~= "") and (", " .. n) or "")
    elseif b:GetClass():GetFName():ToString() == "WBP_Sandbox_Setup_QChallengesPlaque_Overview_C" then
        label = require("qtrials").overview_plaque_label(b)
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
                -- Not an option that cannot be picked: focus skips it, and
                -- Down went from "2 of 4" to "4 of 4" (Pursuit of Happiness,
                -- VM, 2026-10-16). The window's text names it as "Not
                -- available".
                local all = not b:GetIsEnabled()
                for i = 0, list:GetChildrenCount() - 1 do
                    local c = list:GetChildAt(i)
                    if c and c:IsValid() and c:GetClass():GetFName():ToString() == "WBP_MultipleChoice_Button_C"
                        and require("screen").shown(c) and (all or c:GetIsEnabled()) then
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

local poll_again   -- below: one more look on the next tick
local auto_hold_since = nil   -- set while a button in an unread Auto Resolve is held

local function poll()
    -- New windows of a kind seen for the first time, not on screen when
    -- they were made (popups.lua).
    pcall(function() require("popups").recheck_fresh() end)
    -- Info cards the player closed (mouse, Escape): their state, read on
    -- each look, as there is no event (popups.check_gone).
    pcall(function() require("popups").check_gone() end)
    crumb.at("focus: scan buttons")
    local b = focused_button()
    -- Focus left behind a window whose own buttons cannot take it: the
    -- arrows moved the Q Trial profiles under the warning (2026-10-14).
    -- Park it, so the window's button list takes the keys.
    if b then
        crumb.at("focus: focusless window")
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
    -- The same in a room window after a tab switch: focus stayed on the
    -- hidden Management page's Upgrade button, and the Engineering Office's
    -- Work Team Info tab (hull repair) could not be reached (VM, 2026-10-16).
    if b and not require("screen").shown(b) then
        local room_open = false
        for _, w in ipairs(FindAllOf("WBP_RoomManagementV2_C") or {}) do
            if w:IsValid() and live(w) and require("screen").shown(w) then room_open = true end
        end
        if room_open then
            print("[VoyagerAccess] focus: hidden " .. tostring((path_of(b) or ""):match("([^%.]+)$")) .. " in a room window, parked\n")
            M.park_focus()
            b = nil
        end
    end
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
    crumb.at("focus: mod lists")
    if mod_list_open() then
        if b then M.park_focus() end
        return
    end
    -- Answering a call leaves keyboard focus on the HUD's invisible
    -- Incoming calls button, and a No Way Back window that opened then got
    -- no button list: Down did nothing and YES and NO could not be reached
    -- (campaign sector 6, VM, 2026-10-17). With a window open, that focus
    -- does not count.
    if b and (path_of(b) or ""):find("InvisBackButton", 1, true) then
        local okw, wins = pcall(function() return require("popups").open_windows() end)
        if okw and wins and #wins > 0 then
            b = nil
            current = nil
            -- And off it: the game still answers Enter there.
            M.park_focus()
        end
    end
    -- With Gamma open, focus left behind it (a dialogue choice under the
    -- pause menu) does not count either: it dropped Gamma's button list on
    -- every look, and the arrows moved the choices behind (VM, 2026-10-22).
    if b and not (path_of(b) or ""):find("WBP_GammaCorrection_C", 1, true) and gamma_open() then
        b = nil
        current = nil
    end
    crumb.at("focus: first run, radial")
    if not b then b = focus_first_run_screen() end
    if not b then
        local okr, r = pcall(focus_radial)
        if okr then b = r end
    end
    if not b then crumb.at("focus: restore or unfocused window") end
    if b then
        virtual = nil
        last_real = path_of(b)
    elseif not current and not restore_focus() then
        track_unfocused_window()
    end
    local path = b and path_of(b) or nil
    -- After an optional dialogue choice the choices come back on the same
    -- button, focus never changes, and nothing was said; Enter then took the
    -- next choice unheard, three in a row (distress call, VM, 2026-10-15).
    -- A choice seen hidden (the line after it playing) and then shown again
    -- is read again, with the Enter guard.
    local is_choice = path and require("dialogue").is_choice(path)
    local shown_now = is_choice and b and require("screen").shown(b) or false
    if path and path == current and is_choice then
        if not shown_now then
            choice_hidden = true
        elseif choice_hidden then
            choice_hidden = false
            local label = label_for(b, path)
            picked_choice, picked_label = nil, nil
            -- A NEW set of choices can reuse the button that had focus: the
            -- old focus was said ("Choice 2 of 2: Leave the ellipse") and the
            -- game moved focus to its first choice 600 ms later ("Choice 1 of
            -- 2"), the never-reproduced item of the open list (One Small
            -- Step, VM, 2026-10-22). Off the first choice, wait for that move:
            -- the game makes it inside FinishShowChoices, so the choice is
            -- said when that has run (dialogue.after_choices), not after a
            -- fixed 800 ms (firefly82's probe, 2026-10-23). 1500 ms bounds it
            -- if no FinishShowChoices comes.
            local done = false
            local function say_back()
                if done then return end
                done = true
                if current ~= path then return end
                -- The game's own focus, not the mod's record of it: right
                -- after FinishShowChoices the record still named the old
                -- button, and "Choice 2 of 2: Show doubts about the plan" was
                -- said before "Choice 1 of 2" (Equinox, VM, 2026-10-23).
                local ob = resolve(path)
                local still = false
                pcall(function() still = ob and (ob:HasKeyboardFocus() or ob:HasFocusedDescendants()) end)
                if not still then
                    pcall(M.request_check)
                    return
                end
                print("[VoyagerAccess] focus: choices back: " .. tostring(label) .. "\n")
                heard_choice = label and path or nil
                if label then speech.say(label, true) end
            end
            if label and not label:find("^Choice 1 of") then
                require("dialogue").after_choices(say_back)
                ExecuteInGameThreadWithDelay(1500, function() pcall(say_back) end)
            else
                say_back()
            end
        end
        return
    end
    choice_hidden = false
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
    -- when the last key was Enter, Right, Left, Backspace or Escape. The look
    -- now comes after the key that moved focus, so the key is known.
    local inside = zone(current or "") ~= "outside" and zone(path or "") ~= "outside"
    local by_arrow = last_nav == "arrow" or (inside and last_nav ~= "go_in")
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
    if path and not was_choice and require("dialogue").is_choice(path) then heard_choice = nil end
    if path then
        crumb.at("focus: rows")
        local ok, err = pcall(wire_rows, path)
        if not ok then print("[VoyagerAccess] rows error: " .. tostring(err) .. "\n") end
    end
    -- An arrow that moved focus has been used (the menu's crossing check
    -- above, wire_rows' disabled-button skip): forgotten now, or a later
    -- move by the game or a click was taken for an arrow and undone on the
    -- main menu (Fable review, 2026-10-21; 0.3.67 kept it for 2 polls).
    -- "go_in" stays: Enter into a main menu panel can move focus twice
    -- (the panel animates open first) and the second move needs it.
    if last_nav == "arrow" then last_nav = nil end
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
    -- An Overview tab switch: said after the new tab (view.overview_tab).
    -- Any focus, not by path: the Q Challenges entries may have the game
    -- instance as their outer, as the event options do.
    if os.clock() < (require("view").tab_hold_until or 0) then
        print("[VoyagerAccess] focus: held until the Overview tab is read\n")
        return
    end
    -- An event between its choice and its result (popups.lua).
    -- Held until the game shows the result (popups.result_pending), not for
    -- up to 10 s.
    if path:find("WBP_POIMultipleChoice_C", 1, true)
        and (require("popups").result_pending or require("popups").event_unread(path)) then
        print("[VoyagerAccess] focus: held until the event result is read\n")
        return
    end
    -- A story card's Continue: dialogue.lua says "Continue" after the card.
    -- A card its window's events missed is read now (dialogue.card_focused).
    if path:find("WBP_Dialogue_Popup%.WidgetTree_%d+%.ContinueButtonStory$") then
        pcall(function() require("dialogue").card_focused(path) end)
        return
    end
    -- While the game's chances are being read, the option waits: it was
    -- said with the mod's own chances, then again with the game's (Looted
    -- Wreckage, Q Trials, VM, 2026-10-15). The sweep says it at the end.
    -- The options themselves have the game instance as their outer
    -- ("...GameInstance.WBP_POISelectableOption_C_..."), so the window's
    -- name is not in their path and the option was still said twice
    -- (Abandoned Vessel, Q Trials, VM, 2026-10-21).
    if (path:find("WBP_POIMultipleChoice_C", 1, true) or path:find("WBP_POISelectableOption_C", 1, true))
        and require("events").sweeping_now() then return end
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
    -- popups.lua knows which windows the game has opened and which it has
    -- read; asking it replaces a search over these classes on every look.
    local HOLD = { WBP_RoomManagementV2_C = not (okm and map), WBP_POIMultipleChoice_C = true,
        WBP_MultipleChoiceWidget_C = true, WBP_FirstPerformanceSelection_C = true, WBP_GammaCorrection_C = true,
        WBP_BattleResultLCARS_C = true, WBP_SandboxSectorResult_C = true, WBP_CombatAutoResolve_C = true,
        -- "Stay Here, 1 of 2" before "Old Friends, New Enemies.
        -- Completed..." (sector 7, 2026-10-18).
        WBP_MissionInfoWidget_C = true, WBP_SideMissionFinished_C = true,
        -- "Sector 01: Trading Sector, 1 of 3" came before "Leave Sector:
        -- ..." (Q Trial, VM, 2026-10-18).
        WBP_LeaveSector_C = true }
    if popups.unread_of(HOLD) then return end
    -- Auto Resolve inside the battle setup (popups.window_unread): popups
    -- says this button after reading the window. If that read has not come
    -- in 2 s, the button is said then.
    -- A battle's result inside the combat widget too: "Proceed", the
    -- result, then "Proceed" again (demo, Caretaker's test battle, VM,
    -- 2026-10-22).
    local ar = path:match("^(.-%.AutoResolveWidget)%.") or path:match("^(.-%.CombatResultView)%.")
    if ar and popups.window_unread(ar) then
        if not auto_hold_since then
            auto_hold_since = os.clock()
            ExecuteInGameThreadWithDelay(2100, function()
                auto_hold_since = nil
                if popups.window_unread(ar) then pcall(M.reannounce) end
            end)
        end
        return
    end
    -- The battle setup's slots likewise, until "Prepare for combat" is said.
    local okp, prep = pcall(function() return require("awaymission").combat_prep_pending(path) end)
    if okp and prep then
        if not auto_hold_since then
            auto_hold_since = os.clock()
            ExecuteInGameThreadWithDelay(2100, function()
                auto_hold_since = nil
                local ok2, still = pcall(function() return require("awaymission").combat_prep_pending(path) end)
                if ok2 and still then pcall(M.reannounce) end
            end)
        end
        return
    end
    label = with_position(label, path)
    if label then
        if require("dialogue").is_choice(path) then heard_choice = path end
        speech.say(label, true)
    end
end

-- One look after whatever may have moved focus: queued for the next game
-- tick (the game has taken the key by then), and only once however many
-- ask before it runs.
local check_queued = false
function M.request_check()
    if check_queued then return end
    check_queued = true
    ExecuteInGameThread(function()
        check_queued = false
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] focus error: " .. tostring(err) .. "\n") end
    end)
end

-- The focused button is said again on the next look: a hold that ran out
-- without its window being read (the 10 s event result limit, the 2 s
-- grace for a window never shown) left the button it had held unsaid, as
-- the look took it for the one already current (GPT review, 2026-10-21).
function M.reannounce()
    current = nil
    M.request_check()
end

-- A look now and three more shortly after, for focus that moves a moment
-- after a key or a window event: the mod's own delayed SetFocus calls
-- (about 45 of them, dialogue's sector choices 200 ms after Down) and the
-- game's after an animation were never said once looks came only with
-- input (review of firefly82's patch, 2026-10-21). One-off looks, not a
-- loop; a newer request replaces the older one's pending looks.
local settle_token = 0
function M.request_settle()
    settle_token = settle_token + 1
    local mine = settle_token
    M.request_check()
    -- 1500: the main menu took focus after the performance screen's fade,
    -- later than 700 ms, and "CAMPAIGN, 1 of 7" was not said (VM,
    -- 2026-10-21).
    for _, ms in ipairs({ 250, 700, 1500 }) do
        ExecuteInGameThreadWithDelay(ms, function()
            if settle_token == mine then M.request_check() end
        end)
    end
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

-- The live main menu (one object of its class), and the profile buttons of
-- one of its profile columns, read from the menu's own fields
-- (USTVMainMenu: SettingsButton, DLCButton, ProfileButtonParent,
-- SandboxProfileButtonParent, SectorSaveWindow) instead of searching every
-- button in the game.
local function main_menu()
    for _, w in ipairs(FindAllOf("WBP_MainMenu_C") or {}) do
        if w:IsValid() and live(w) then return w end
    end
    return nil
end
local function profile_buttons(menu)
    local out = {}
    for _, field in ipairs({ "ProfileButtonParent", "SandboxProfileButtonParent" }) do
        pcall(function()
            local box = menu[field]
            if not (box and box:IsValid()) then return end
            for i = 0, box:GetChildrenCount() - 1 do
                local c = box:GetChildAt(i)
                if c and c:IsValid() then out[#out + 1] = c end
            end
        end)
    end
    return out
end

-- RULE EXCEPTION, kept on purpose (review of 0.3.70, 2026-10-22): this sets
-- three of the game's widget fields itself, which is the mod doing what the
-- game's hover does. The game gives the keyboard no way of its own here,
-- proven in the main menu probes (Audit-Hauptmenue.md): Right on a profile
-- calls the game's SectorProfileNavigated but leaves the save window empty
-- (ProfileIndex -1), and a click only selects the profile (BP_OnSelected);
-- only the mouse hover fills it, in C++ that Lua cannot call, and a real
-- hover needs the button's place on screen, which Lua cannot read (FGeometry
-- comes back empty, 2026-10-20).
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

-- Runs fn once the animated switcher that get_switcher() returns has
-- finished fading to its new page. The main menu's panels
-- (UCommonAnimatedSwitcher) and the settings window's pages (its subclass
-- UCommonActivatableWidgetSwitcher) fade in, and a click or focus during
-- the fade does not reach the new page. The game reports no end of the
-- fade: no event of the menu, the settings window or its tabs came (probes
-- 2026-10-22, Audit-Hauptmenue.md). What the game does say is its state,
-- IsTransitionPlaying, and the fade's own length, TransitionDuration (the
-- engine's 0.4 s; no setting changes it; a settings tab was done at 400 ms
-- in the probe). So: no fade, fn at once (the campaign profiles open
-- without one); a fade, one look after the game's own duration, and one
-- more after the same again if a slow frame kept it going, then fn either
-- way. Replaces 0.3.70's look every 100 ms for up to 1.5 s (panels) and
-- its fixed 400 ms (settings tabs).
local function when_switched(get_switcher, fn, what)
    local function fading()
        local sw = nil
        pcall(function() sw = get_switcher() end)
        local ok, playing = pcall(function() return sw:IsTransitionPlaying() end)
        return ok and playing == true, sw
    end
    local function go(note)
        if note then print("[VoyagerAccess] " .. what .. ": " .. note .. "\n") end
        local ok, err = pcall(fn)
        if not ok then print("[VoyagerAccess] " .. what .. ": " .. tostring(err) .. "\n") end
    end
    local now, sw = fading()
    if not now then return go() end
    local okd, dur = pcall(function() return sw.TransitionDuration end)
    if not (okd and type(dur) == "number" and dur > 0) then
        return go("fading, no duration from the game, going on now")
    end
    local ms = math.ceil(dur * 1000)
    ExecuteInGameThreadWithDelay(ms, function()
        if not fading() then return go() end
        ExecuteInGameThreadWithDelay(ms, function()
            go(fading() and "still fading after twice its duration, going on" or nil)
        end)
    end)
end

-- Clicks the main menu button at button_path once the panel the mod has just
-- opened is up (when_switched on the menu's ContentPanel).
local function click_when_panel_up(menu_path, button_path)
    pending_click = { button = button_path, menu = menu_path }
    local mine = pending_click
    when_switched(function() return resolve(menu_path).ContentPanel end, function()
        if pending_click ~= mine then return end
        pending_click = nil
        local button = resolve(button_path)
        if button then click(button) end
    end, "enter")
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
    -- A major decision's choices stay on screen after one is picked, so
    -- every Enter that moved the next lines on said "Holding" and held the
    -- picked choice again (Idrin's relay, sector 7, 2026-10-18). Once a
    -- choice has been picked, Enter on that same choice continues.
    local picked_path = current and (current:match("^(.-WBP_Dialogue_Choice_Sector_C_%d+)") or current:match("^(.-WBP_Dialogue_Choice_C_%d+)"))
    if choice and picked_path and picked_path == picked_choice and picked_label ~= label_for(choice, current) then
        picked_choice, picked_label = nil, nil
    end
    if choice and picked_path and picked_path == picked_choice and dialogue.active() then
        print("[VoyagerAccess] enter: choice already picked, continuing\n")
        dialogue.continue()
        return
    end
    -- The Enter that moves the last line on can land just as the choices
    -- come up, and it picked "Choice 1" before it was heard (twice,
    -- 2026-10-14). Enter picks only a choice whose label has been said;
    -- otherwise it says it (was: within a second of the choices appearing).
    if choice and require("screen").shown(choice) and heard_choice ~= current then
        local label = label_for(choice, current)
        print("[VoyagerAccess] enter: choice not heard yet, reading it\n")
        heard_choice = label and current or nil
        if label then speech.say(label, true) end
        return
    end
    if choice and require("screen").shown(choice) then
        local cpath = current:match("^(.-WBP_Dialogue_Choice_Sector_C_%d+)") or current:match("^(.-WBP_Dialogue_Choice_C_%d+)")
        local c = cpath and resolve(cpath)
        local target = c and c.RightButton
        if not (target and target:IsValid()) then target = resolve(current) end
        -- A choice that cannot be taken: Enter did nothing and said nothing
        -- (stickbear, forum, 2026-10-19: "pressing enter should give some
        -- kind of feedback"). Say so, with the game's own requirement.
        local okd, off = pcall(function() return not c.LeftButton:GetIsEnabled() end)
        if okd and off then
            local l = label_for(choice, current) or ""
            local need = l:match("(Needs [^%.]+)")
            speech.say("Not available" .. (need and (". " .. need) or "") .. ".", true)
            return
        end
        if target then
            print("[VoyagerAccess] enter: choice " .. tostring(current) .. "\n")
            -- The Array's "Destroy the Array or go home" choice is a hold
            -- button (bRequiresHold); a click did nothing, fourteen times
            -- (2026-10-14). Hold it as Wait One Cycle is held.
            local okh, hold = pcall(function() return target.bRequiresHold end)
            if okh and hold then
                picked_choice, picked_label = cpath, label_for(resolve(current), current)
                speech.say("Holding", true)
                target:HandleButtonPressed()
                local held = path_of(target)
                ExecuteInGameThreadWithDelay(require("screen").hold_ms(target), function()
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
        or gamma_open()
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
                -- Enter on the chosen card takes it back: that was said as
                -- "Chosen, rewards selected 0 of 1" (VM, 2026-10-16).
                if n:match("^0 ") then
                    popups.meta_chosen = nil
                    speech.say("Choice removed, rewards selected " .. n, true)
                    return
                end
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
        -- In the full game Restart Sector's click only made it "selected"
        -- and its column of sector saves stayed collapsed, after a game
        -- over and again on every try (VM, 2026-10-16). When the click has
        -- not shown them, the window's UpdateShowLoadSaveButtons does, and
        -- focus moves to the first save that can be loaded.
        -- At once, not 400 ms later (probes 2026-10-22): the click never
        -- shows the list (it only selects the button; the game's own Right,
        -- NavigatedSectorSaveButton, does not either: the list opens on
        -- hover or gamepad focus), and after UpdateShowLoadSaveButtons(true)
        -- the saves are shown and the first is focusable in the same call.
        if name == "SectorSaveButton" then
            ExecuteInGameThread(function()
                pcall(function()
                    local function any_shown()
                        for _, x in ipairs(FindAllOf("WBP_Button_LoadSectorSave_C") or {}) do
                            if x:IsValid() and require("screen").shown(x) then return true end
                        end
                        return false
                    end
                    -- The demo needed a second Enter (the first only
                    -- selected it): focus goes into a list already shown.
                    if current and current:find("WBP_Button_LoadSectorSave_C", 1, true) then return end
                    local shown = any_shown()
                    for _, w in ipairs(FindAllOf("WBP_LoadSectorSaveWindow_C") or {}) do
                        if w:IsValid() and live(w) and require("screen").shown(w) then
                            print("[VoyagerAccess] enter: save window list, shown " .. tostring(shown) .. "\n")
                            if not shown then w:UpdateShowLoadSaveButtons(true) end
                            -- GetFirstEnabledSectorSaveButton fails in the
                            -- demo; then the first one shown, in list order.
                            local okf, first = pcall(function() return w:GetFirstEnabledSectorSaveButton() end)
                            if not (okf and first and first:IsValid()) then
                                first = nil
                                local best = math.huge
                                for _, x in ipairs(FindAllOf("WBP_Button_LoadSectorSave_C") or {}) do
                                    if x:IsValid() and require("screen").shown(x) then
                                        local i = 0
                                        pcall(function() i = x:GetParent():GetChildIndex(x) end)
                                        if i < best then first, best = x, i end
                                    end
                                end
                            end
                            if first then first:SetFocus() end
                        end
                    end
                end)
            end)
        end
    end
    -- The room's hero when its hero list is opened: closing the list
    -- without a choice leaves the room with no hero (see go_back).
    if current:find("WBP_HeroModule_C_%d+%..*OpenSelectionButton$") then
        local okl, l = pcall(label_for, b, current)
        M.room_hero_before = okl and type(l) == "string" and l:match("^Assigned hero: ([^%.]+)") or nil
    end
    -- The same for an away team or battle slot: leaving its list with
    -- Escape or Backspace emptied the slot (Harry Kim left a battle slot,
    -- VM, 2026-10-16). See restore_slot_hero.
    -- Reset only by a slot's own Enter: Enter on an unavailable hero in the
    -- list picked nobody, and the Escape after it lost Harry Kim (VM,
    -- 2026-10-16). A hero that was really chosen leaves the slot filled,
    -- so restore_slot_hero does nothing then.
    if require("awaymission").is_slot(current) then
        M.slot_before = nil
        local okl, l = pcall(require("awaymission").slot_label, current)
        local hero = okl and type(l) == "string" and l:match("slot %d+ of %d+: ([^,%.]+)")
        if hero then M.slot_before = { path = current, hero = hero } end
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
    confirm_order(b, current, radial_said[current])
    -- A Workshop blueprint: say that crafting began, as an analysis says
    -- "Analysis started" (it said nothing, VM, 2026-10-17).
    if b:GetClass():GetFName():ToString() == "WBP_ItemButton_C" then
        local before = require("rooms").crafting_now()
        ExecuteInGameThreadWithDelay(900, function()
            pcall(function()
                local now = require("rooms").crafting_now()
                if now and now ~= before then speech.say("Crafting " .. now .. " started", true) end
            end)
        end)
    end
    if b:GetClass():GetFName():ToString() == "WBP_RadialButton_C" then
        -- A segment the game has locked (bLocked): Clear Debris with no life
        -- support did nothing and said nothing on Enter (VM, 2026-10-15).
        -- Say why, from what the ring said for it ("Clear Debris. No Life
        -- Support. ...").
        local okl, locked = pcall(function() return b.bLocked == true end)
        -- A room to build is checked by construction.enter from the game's
        -- data; its lock flag can be stale (still set after the duranium
        -- came in, VM, 2026-10-17).
        local okr, room = pcall(require("construction").command_of, b)
        if okr and room then locked = false end
        if okl and locked then
            local said = radial_said[current] or ""
            local name, why = said:match("^([^%.]+)%.%s*([^%.]+)")
            -- Only a reason the ring gave ("No Life Support", "Missing
            -- resources: ..."): a segment still locked from before the
            -- resources came in said "Not possible: Accommodates 10 CREW
            -- ..." (VM, 2026-10-17). Closing and opening the ring again
            -- clears that lock.
            -- The game's own error for the segment, in its language; the
            -- English check this replaced ("^No ") missed "Keine
            -- Lebenserhaltung" (firefly82's review, 2026-10-19). "Missing
            -- resources" is the mod's own wording (construction.lua).
            local err = radial_error[current]
            -- With no reason from the game, only "Not possible": the mod's
            -- guesses ("the ring may be out of date", busy work teams) were
            -- wrong where the game said "Keine Lebenserhaltung" (firefly82's
            -- review, 2026-10-20).
            if err and err ~= "" then why = (err:gsub("%.%s*$", ""))
            elseif why and not why:find("^Missing resources") then why = nil end
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
    local function focus_page(win)
        local page = (win or window).ContentPanel:GetActiveWidget()
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
        -- The window is looked up again by its path after the fade, never
        -- kept across ticks (GPT review, 2026-10-22).
        local wpath = path_of(window)
        -- The new page fades in (the window's own switcher); focus goes in
        -- once it is there, not after a fixed 400 ms (when_switched).
        when_switched(function() return resolve(wpath).ContentPanel end, function()
            local w = resolve(wpath)
            if current == tab and w then focus_page(w) end
        end, "settings tab")
        return
    end
    local menu = open_panel_for(b)
    if menu then
        -- The click moves focus into the panel only once the panel is up;
        -- in the same tick it did nothing, and one poll later it still
        -- failed about half the time (Casey had to press Enter twice).
        click_when_panel_up(path_of(menu), current)
    else
        -- A Q Trials hero is chosen or removed with its own announcement.
        if require("qtrials").enter(b, current) then return end
        -- An event option with a hero chosen (Left and Right).
        if require("events").enter(b, current) then return end
        -- Any other button the game shows switched off: say so, with the
        -- reason its label gives, instead of nothing (stickbear, forum,
        -- 2026-10-19: "hey you can't do that, here's why").
        local oke, en = pcall(function() return b:GetIsEnabled() end)
        if oke and en == false then
            local l = label_for(b, current) or ""
            local why = l:match("(Needs [^%.]+)") or l:match("Not possible: ([^%.]+)") or l:match("[Nn]ot available: ([^%.]+)")
            speech.say("Not available" .. (why and (". " .. why) or "") .. ".", true)
            return
        end
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
            -- Clicked only when the card shows its store link: the state
            -- text is translated ("Installed" only in English), and owned
            -- and "Coming soon" cards both hide VisitStorePageContainer
            -- (Casey's machine, 2026-10-17). ShouldShowStorePage returned
            -- false for every card, owned or not, so it cannot tell them apart.
            local okv, store = pcall(function() return require("screen").shown(b.VisitStorePageContainer) end)
            if okv and store then click(b) end
            return
        end
        local before = label_for(b, current)
        local path = current
        -- A hold button (Custom difficulty's Start Game, bRequiresHold)
        -- ignores a click: hold it, as dialogue choices and Wait One Cycle
        -- are held.
        local okh, hold = pcall(function() return b.bRequiresHold end)
        if okh and hold then
            -- A Leave Sector entry's hold confirms the window's selected
            -- exit, not the entry held, and the selection had stayed on the
            -- sector focus passed through: Sector 01 was heard and held, and
            -- Voyager went to Sector 02 (Q Trial, VM, 2026-10-22). The held
            -- entry is selected first, and again before the release.
            local exit_entry = b:GetClass():GetFName():ToString() == "WBP_LeaveSectorEntry_C"
            if exit_entry then pcall(function() b:NotifySelected() end) end
            speech.say("Holding", true)
            b:HandleButtonPressed()
            ExecuteInGameThreadWithDelay(require("screen").hold_ms(b), function()
                pcall(function()
                    local nb = resolve(path)
                    -- Its own pcall: an error here must not skip the release.
                    if nb and exit_entry then pcall(function() if not nb:IsSelectedExit() then nb:NotifySelected() end end) end
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
                    -- Energy only when it is short: a Cargo Bay with 108
                    -- energy and 51 in use stayed inactive, and naming the
                    -- energy sent the player the wrong way. The game shows
                    -- no reason of its own then (Q Trial, VM, 2026-10-18).
                    if info.EnergyAmount - info.EnergyConsumption < 10 then
                        speech.say(string.format("Did not switch. Energy %d, rooms use %d.",
                            info.EnergyAmount, info.EnergyConsumption), true)
                    else
                        speech.say("Did not switch. The game shows no reason.", true)
                    end
                end)
            end
        end
        ExecuteInGameThreadWithDelay(300, function() check(8) end)
    end
end

-- After Escape or Backspace leaves an away team or battle hero list: the
-- game takes the slot's hero out when its list closes without a choice.
-- The mod used to open the slot again and choose the same hero; now it
-- leaves what the game did and says it, "Joe Carey removed" before the slot
-- ("..., empty"), and the player chooses (firefly82's review; Casey,
-- 2026-10-23).
function M.restore_slot_hero()
    local before = M.slot_before
    if not before then return end
    M.hush_focus_until = os.clock() + 1
    ExecuteInGameThreadWithDelay(500, function()
        M.hush_focus_until = 0
        pcall(function()
            local away = require("awaymission")
            local okl, l = pcall(away.slot_label, before.path)
            if not (okl and type(l) == "string" and l:find("empty", 1, true)) then return end
            M.slot_before = nil
            print("[VoyagerAccess] back: " .. before.hero .. " removed from the slot\n")
            speech.say(require("tr").fill("{s} removed", before.hero) .. ". " .. l, true)
        end)
    end)
end

-- Backspace: return focus to the button Enter was last pressed on. The game
-- has no keyboard Back of its own (Escape does not close the save panel).
local function go_back()
    crumb.at("key: backspace")
    if require("qtrials").back(current) then return end
    if require("awaymission").is_hero_button(current or "") then M.restore_slot_hero() end
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
                    -- out of the room, with the game's Escape too (Neelix
                    -- left the Mess Hall on Backspace, VM, 2026-10-15). The
                    -- mod used to open the list again and choose him again;
                    -- now it does what the game does and says so, and the
                    -- player chooses (firefly82's review; Casey, 2026-10-23).
                    local keep = cls:find("Room", 1, true) and M.room_hero_before
                    -- Quiet until the line below: "Assign a hero" came twice,
                    -- once from focus and once after "Chakotay removed" (demo).
                    if keep then M.hush_focus_until = os.clock() + 0.6 end
                    w:CallBackAction()
                    if keep then
                        ExecuteInGameThreadWithDelay(400, function()
                            M.hush_focus_until = 0
                            pcall(function()
                                local okl, l = pcall(M.current_label)
                                local removed = require("tr").fill("{s} removed", keep)
                                speech.say(removed .. ((okl and l) and (". " .. l) or ""), true)
                            end)
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
        local menu = main_menu()
        local b = menu and menu.SettingsButton
        if b and b:IsValid() and require("screen").shown(b) then
            print("[VoyagerAccess] back: main menu SETTINGS\n")
            b:SetFocus()
            return
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
        -- Now, not 300 ms later: the panel is closed (IsActivated false)
        -- in the same call as the click, and the game does not move focus
        -- back to the DLC button itself (probe 2026-10-22).
        pcall(function()
            local menu = menu_path and resolve(menu_path)
            local b = menu and menu.DLCButton
            if b and b:IsValid() then b:SetFocus() end
        end)
        return
    end
    -- In a save slot's panel (CONTINUE GAME, NEW GAME, NEW Q TRIAL), back to
    -- the slot it belongs to: from an empty Q Trial slot's NEW Q TRIAL no
    -- key led back (Up, Left, Backspace and Escape all did nothing, VM,
    -- 2026-10-16).
    if current and current:find("%.SectorSaveWindow%.") then
        local menu_path = current:match("^(.-WBP_MainMenu_C_%d+)")
        local menu = menu_path and resolve(menu_path)
        local pick, first = nil, nil
        for _, x in ipairs(menu and profile_buttons(menu) or {}) do
            if require("screen").shown(x) then
                first = first or x
                local oks, sel = pcall(function() return x:GetSelected() end)
                if oks and sel then pick = x end
            end
        end
        pick = pick or first
        if pick then
            print("[VoyagerAccess] back: save slot\n")
            pick:SetFocus()
            return
        end
    end
    -- In a ring (the build ring's room page), up one level as its Back
    -- button does: Backspace said "Nothing to go back to" there (VM,
    -- 2026-10-16). From the top level this closes the ring.
    for _, w in ipairs(FindAllOf("WBP_RadialMenu_C") or {}) do
        if w:IsValid() and require("screen").shown(w) and pcall(function() w:GoBackToLastMenu() end) then
            print("[VoyagerAccess] back: radial up one level\n")
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

-- A window with one button (the "Final Warning" mission card) gives the
-- arrows and Home nowhere to go, so focus never changed and nothing was
-- said (VM, 2026-10-23). When focus has stayed on a button that is alone
-- in its list, it is said again, as a sighted player still sees it.
local function say_if_alone()
    local before = current
    if not before then return end
    ExecuteInGameThreadWithDelay(300, function()
        if current ~= before then return end
        pcall(function()
            local b = resolve(current)
            if not (b and require("screen").shown(b)) then return end
            if groups[current] and #groups[current] > 1 then return end
            BUTTON = BUTTON or StaticFindObject("/Script/CommonUI.CommonButtonBase")
            local list, n = b:GetParent(), 0
            for i = 0, list:GetChildrenCount() - 1 do
                local row = list:GetChildAt(i)
                if row and row:IsValid() and row:IsA(BUTTON) and require("screen").shown(row) then n = n + 1 end
            end
            if n > 1 then return end
            local okl, l = pcall(M.current_label)
            if okl and type(l) == "string" and l ~= "" then speech.say(l, true) end
        end)
    end)
end
M.say_if_alone = say_if_alone

local function edge(last)
    crumb.at("key: home/end")
    local b = resolve(current)
    if not b then return end
    if require("dialogue").choice_edge(current, last) then return end
    say_if_alone()
    BUTTON = BUTTON or StaticFindObject("/Script/CommonUI.CommonButtonBase")
    -- A button with no button siblings (Confirm below the Q Modifier
    -- cards, which live outside the window; Home and End did nothing, VM,
    -- 2026-10-16): the list it is counted in.
    local list = b:GetParent()
    local siblings = 0
    pcall(function()
        for i = 0, list:GetChildrenCount() - 1 do
            local row = list:GetChildAt(i)
            if row and row:IsValid() and row:IsA(BUTTON) and require("screen").shown(row) then siblings = siblings + 1 end
        end
    end)
    -- Counted again first: Confirm appears only after a reward is chosen,
    -- and the first End went to "3 of 4" from the old count (VM, 2026-10-17).
    -- Only when the new count still has the focused button: from an away
    -- team hero picker it counted the team screen, and Home left the
    -- picker for the slot (VM, 2026-10-17).
    -- So only buttons this count already had are counted again.
    local before = groups[current]
    local function has(list)
        for _, m in ipairs(list or {}) do if m == current then return true end end
        return false
    end
    if has(before) then pcall(wire_rows, current) end
    local members = groups[current]
    if not has(members) then members = before end
    -- Or a list counted wider than its panel: End on the Q Trials results
    -- stopped on the last reward, "3 of 4", short of Confirm (VM, 2026-10-17).
    if members and #members >= 2 and (siblings < 2 or #members > siblings) then
        local from, to, step = 1, #members, 1
        if last then from, to, step = #members, 1, -1 end
        for i = from, to, step do
            local row = resolve(members[i])
            if row and require("screen").shown(row) then row:SetFocus() return end
        end
    end
    if not (list and list:IsValid()) then return end
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
        -- A room page with nothing to focus (the Aeroshuttle Bay's Trading
        -- tab, "Awaiting new trade offers") passed Down to the ship view
        -- behind the window (VM, 2026-10-16).
        if require("rooms").window_open() then return false end
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
        last_nav = "go_in"   -- a panel may animate open first; focus moves in after
        if require("popups").close_tutorial() then return end
        if require("whatsnew").open() then return require("whatsnew").close() end
        if require("hotkeys").open() then return require("hotkeys").repeat_item() end
        if require("credits").open() then return require("credits").repeat_item() end
        if require("techtree").open() then return require("techtree").enter() end
        if ship.list_open() then return ship.list_enter() end
        if require("resources").list_open() then return require("resources").enter() end
        if require("view").nav_open() then return require("view").nav_enter() end
        if away.keys_active() then return away.mission_enter() end
        if require("view").overview_list_repeat() then return end
        if M.virtual_active() then return M.virtual_enter() end
        -- In battle with no wheel open, Enter opens Orders (combat.lua).
        -- Not while focus is in the battle setup (HeroLoadout): Enter on Auto
        -- Resolve opened Orders there, and that started the battle by hand.
        -- The setup counted as not shown at that moment (Casey's machine,
        -- 2026-10-15, Vidiian ambush).
        -- Nor just after the setup closed: the Enter that started the battle
        -- reached the mod after focus had moved into it, and opened Orders
        -- (1 of 3 starts, Casey's machine, 2026-10-16).
        local recent_setup = os.time() - (require("combat").setup_last or -100) < 2
        if require("combat").active() and not recent_setup and not (current and current:find(".HeroLoadout.", 1, true)) then
            local fb = resolve(current)
            if not (fb and require("screen").shown(fb)) then return require("combat").open_orders() end
        end
        if ship_mode() then return ship.open() end
        if map_mode() then return system.enter() end
        activate()
    end)
    keys.on("backspace", function()
        last_nav = "go_in"
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
        last_nav = "go_in"
        -- Escape is the game's: its pause menu opens as for anyone. A mod
        -- list open at the time still closes, so the arrows go back to the
        -- game, but the pause menu is no longer clicked away behind the
        -- player's back; Backspace closes a mod list without it (firefly82's
        -- review; Casey, 2026-10-23).
        local closed = require("whatsnew").close() or require("hotkeys").close() or ship.list_close() or require("resources").close()
            or require("view").nav_close() or (map_mode() and system.menu_close())
        if closed then return end
        -- The first Escape on the map closes a point's details panel, which
        -- a sighted player sees go; it was silent (VM, 2026-10-21).
        if map_mode() then
            local details = {}
            for _, wp in ipairs(require("popups").open_windows()) do
                -- Named parts of the HUD ("...WidgetTree_n.POIDetailView"),
                -- so the class name is not in the path.
                if wp:find("POIDetailView", 1, true) or wp:find("PlanetDetailView", 1, true)
                    or wp:find("ShipDetailView", 1, true) then details[#details + 1] = wp end
            end
            if #details > 0 then
                ExecuteInGameThreadWithDelay(300, function()
                    pcall(function()
                        for _, wp in ipairs(details) do
                            local w = StaticFindObject(wp)
                            if w and w:IsValid() and require("screen").shown(w) then return end
                        end
                        speech.say("Closed", true)
                    end)
                end)
            end
        end
        if require("awaymission").is_hero_button(current or "") then M.restore_slot_hero() return end
        -- A ring (radial menu) whose only action is disabled keeps the
        -- focus on that button, and the game's Escape left it open ("Clear
        -- Debris. No available work team", Q Trial, VM, 2026-10-16). If a
        -- ring is still up shortly after Escape, its back action closes it.
        local rings = {}
        for _, w in ipairs(FindAllOf("WBP_RadialMenu_C") or {}) do
            if w:IsValid() and require("screen").shown(w) then rings[#rings + 1] = path_of(w) end
        end
        if #rings > 0 then
            ExecuteInGameThreadWithDelay(400, function()
                for _, p in ipairs(rings) do
                    pcall(function()
                        local w = StaticFindObject(p)
                        if w and w:IsValid() and require("screen").shown(w) then
                            w:CallBackAction()
                            print("[VoyagerAccess] escape: back action on " .. p:match("([%w_]+)$") .. "\n")
                        end
                    end)
                end
            end)
        end
        -- A window whose controls are all disabled has nothing for the game
        -- to focus, and the game's Escape does nothing without focus: a
        -- damaged Aeroshuttle Bay with no free work team could not be
        -- closed (VM, 2026-10-16). Its back action closes it, as the
        -- game's Escape would.
        local b = resolve(current)
        if b and require("screen").shown(b) then return end
        local targets = {}
        if M.virtual_active() and M.virtual_window() then targets[#targets + 1] = M.virtual_window() end
        if require("rooms").window_open() then
            for _, w in ipairs(FindAllOf("WBP_RoomManagementV2_C") or {}) do
                if w:IsValid() and require("screen").shown(w) then targets[#targets + 1] = path_of(w) end
            end
        end
        -- The tech tree just opened keeps no focus (techtree parks it), and
        -- Escape left it open (VM, 2026-10-21). Not with a technology's
        -- panel open: that Escape closes only the panel, and the back
        -- action closed the tree as well.
        if require("techtree").open() and not require("techtree").panel_open() then
            for _, w in ipairs(FindAllOf("WBP_TechTreeView_C") or {}) do
                if w:IsValid() and require("screen").shown(w) then targets[#targets + 1] = path_of(w) end
            end
        end
        -- Only if it is still up a moment later, as with the rings above: the
        -- game's own Escape may be closing it at the same time, and a second
        -- back action left the Overview half open (outside review, 2026-10-17).
        if #targets == 0 then return end
        ExecuteInGameThreadWithDelay(400, function()
            for _, p in ipairs(targets) do
                local w = StaticFindObject(p)
                if w and w:IsValid() and require("screen").shown(w) and pcall(function() w:CallBackAction() end) then
                    print("[VoyagerAccess] escape: back action on " .. p:match("([%w_]+)$") .. "\n")
                    undo_pause()
                    return
                end
            end
        end)
    end)
    -- Lists move with Up and Down everywhere (Casey, 2026-10-10); Left and
    -- Right change values. Page Up and Down change deck in the ship view.
    keys.on("up", function()
        pcall(require("combat").energy_key)
        if require("qtrials").step(current, -1) then return end
        if require("popups").leave_sector_step(current, -1) then return end
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
        elseif require("view").overview_list_step(-1) then return
        elseif M.virtual_active() then M.virtual_step(-1)
        elseif require("warpcore").handles(current) then require("warpcore").move(current, 1)
        elseif require("dialogue").choice_step(current, -1) then last_dir = -1 last_nav = "arrow"
        elseif ship_mode() then ship.deck(-1)
        elseif map_mode() then if system.menu_open() then system.menu_step(-1) else system.step(-1) end
        else last_dir = -1 last_nav = "arrow" say_if_alone() end
    end)
    keys.on("down", function()
        pcall(require("combat").energy_key)
        if require("qtrials").step(current, 1) then return end
        if require("popups").leave_sector_step(current, 1) then return end
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
        elseif require("view").overview_list_step(1) then return
        elseif M.virtual_active() then M.virtual_step(1)
        elseif require("warpcore").handles(current) then require("warpcore").move(current, -1)
        elseif require("dialogue").choice_step(current, 1) then last_dir = 1 last_nav = "arrow"
        elseif ship_mode() then ship.deck(1)
        elseif map_mode() then if system.menu_open() then system.menu_step(1) else system.step(1) end
        else last_dir = 1 last_nav = "arrow" say_if_alone() end
    end)
    local rooms = require("rooms")
    keys.on("left", function()
        pcall(require("combat").energy_key)
        last_nav = "go_in"
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
        last_nav = "go_in"
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
        if require("view").overview_list_step(last and 1 or -1, true) then return end
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
    -- A look after every key and mouse button (keys.lua), and one now for
    -- whatever has focus as the mod starts; windows and dialogue ask for
    -- theirs (popups.lua, dialogue.lua). No loop.
    keys.on_any(M.request_settle)
    M.request_check()
    print("[VoyagerAccess] focus: looks after input and window changes\n")
end

return M
