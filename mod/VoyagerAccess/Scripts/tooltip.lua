-- Reads one of the game's hover panels as lines for a details list
-- (Casey, 2026-10-19: what a sighted player reads by resting the mouse on
-- something, as a list to take one's time with). firefly82's review
-- (2026-10-19, section 21a) laid out the method, tested by them: walk the
-- panel's own widget tree only (never a search over every widget), take
-- the text blocks shown inside it, in tree order, and name the icons that
-- stand for words.
--
-- The ship view's info panel (WBP_Sideview_InfoPanel, read in the VM on
-- 2026-10-19): RoomNameText, Level_Text "Lvl" and UpgradeLevelText "01",
-- EnergyConsumedText and CrewAmountText beside icons, the E key icon
-- (MI_MKB_Btn_E) before InputName "Repair", and each cost as a resource
-- icon (MI_UI_Duranium_WhiteNoBG) before Resource_Value "8".

local screen = require("screen")
local text = require("text")

local M = {}

-- Numbers whose label is an icon, named by the widget (any language).
local NUMBER_NAMES = { EnergyConsumedText = "Energy", CrewAmountText = "Crew" }
local RESOURCE_WORDS = { BioNeuralGelPack = "bio-neural gel pack", BorgNanites = "Borg nanites",
    SciencePoints = "science points", Cycle = "cycles", Crews = "crew", Crew = "crew" }

-- Only icons that stand for a resource are named; the rest are decoration
-- ("hud", "icon", "moraleconditions" came out of the resource tooltips).
local RESOURCE_ICONS = { Deuterium = true, Duranium = true, Tritanium = true, Food = true,
    Dilithium = true, SciencePoints = true, BioNeuralGelPack = true, BorgNanites = true,
    Energy = true, Crews = true, Crew = true, Cycle = true }

local function resource_of(raw)
    local r = raw:match("^MI_UI_(%a+)_") or raw:match("^MI_UI_(%a+)$")
    if not (r and RESOURCE_ICONS[r]) then return nil end
    return text.game_resource_name(r == "Crews" and "Crew" or r) or RESOURCE_WORDS[r] or r:lower()
end

-- Tokens in tree order: { kind = "text", name, value } or { kind = "key" }
-- or { kind = "res", word }.
local function tokens(root)
    local W = StaticFindObject("/Script/UMG.UserWidget")
    local P = StaticFindObject("/Script/UMG.PanelWidget")
    local I = StaticFindObject("/Script/UMG.Image")
    local out, count = {}, 0
    local function walk(w, depth)
        if depth > 30 or count > 400 or not (w and w:IsValid()) then return end
        count = count + 1
        if w:IsA(I) then
            if screen.shown(w, root) then
                pcall(function()
                    local ro = w.Brush.ResourceObject
                    if not (ro and ro:IsValid()) then return end
                    local raw = ro:GetFName():ToString()
                    local key = raw:match("^MI_MKB_Btn_(%w+)$")
                    if key then out[#out + 1] = { kind = "key", key = key } return end
                    local res = resource_of(raw)
                    if res then out[#out + 1] = { kind = "res", word = res } end
                end)
            end
            return
        end
        local ok, t = pcall(function() return w:GetText():ToString() end)
        if ok and type(t) == "string" then
            local name = w:GetFName():ToString()
            -- The dim leading zeros on number panels (firefly82).
            if t ~= "" and not name:find("^FillDigits") and screen.shown(w, root) then
                local s = (text.prep(t):gsub("<[^>]*>", ""):gsub("{/n}", " "):gsub("%s+", " "):match("^%s*(.-)%s*$"))
                if s ~= "" then out[#out + 1] = { kind = "text", name = name, value = s } end
            end
            return
        end
        if w:IsA(W) then
            local tree = w.WidgetTree
            if tree and tree:IsValid() and tree.RootWidget then walk(tree.RootWidget, depth + 1) end
        elseif w:IsA(P) then
            for i = 0, w:GetChildrenCount() - 1 do walk(w:GetChildAt(i), depth + 1) end
        end
    end
    walk(root, 0)
    return out
end

-- The panel as list lines: a key and the action after it with its costs
-- on one line ("E: Repair, 8 duranium, 4 tritanium"), "Lvl" with its
-- number, icon numbers named.
function M.lines(root)
    local list, line = {}, nil
    local res = nil
    local function flush()
        if line then list[#list + 1] = line end
        line = nil
    end
    local toks = tokens(root)
    local i = 1
    while i <= #toks do
        local t = toks[i]
        if t.kind == "key" then
            flush()
            local nx = toks[i + 1]
            if nx and nx.kind == "text" then
                line = t.key .. ": " .. nx.value
                i = i + 1
            else
                line = t.key
            end
        elseif t.kind == "res" then
            res = t.word
        elseif t.kind == "text" then
            local function number(v) return v:match("^[%+%-]?[%d%.,]+$") or v == "-" end
            local nxt = toks[i + 1]
            if nxt and nxt.kind == "res" then nxt = toks[i + 2] end
            if res and number(t.value) then
                local item = t.value .. " " .. res
                if line then line = line .. ", " .. item else list[#list + 1] = item end
                res = nil
            elseif not number(t.value) and t.value ~= "/" and not NUMBER_NAMES[t.name]
                and t.name ~= "Level_Text" and nxt and nxt.kind == "text" and number(nxt.value) then
                -- A label and its value on one line ("Current Amount 2800"),
                -- with "/ 60" after it ("Idling 48 / 60"), as the screen
                -- sets them side by side.
                flush()
                local j = i + 1
                if toks[j].kind == "res" then res = toks[j].word; j = j + 1 end
                local v = toks[j].value
                -- With an icon between, the number is an amount of its own,
                -- not this label's value: "Torpedo-Abschussrampe -6 energy"
                -- glued a room's name to its energy (firefly82's review,
                -- 2026-10-20).
                local sep = res and ", " or " "
                if res then v = v .. " " .. res; res = nil end
                line = t.value .. sep .. v
                while toks[j + 2] and toks[j + 1].kind == "text" and toks[j + 1].value == "/"
                    and toks[j + 2].kind == "text" and number(toks[j + 2].value) do
                    line = line .. " / " .. toks[j + 2].value
                    j = j + 2
                end
                flush()
                i = j
            elseif number(t.value) and not NUMBER_NAMES[t.name] and nxt and nxt.kind == "text"
                and not number(nxt.value) and nxt.value ~= "/" and #nxt.value <= 20
                and nxt.name ~= "Level_Text" and not NUMBER_NAMES[nxt.name] then
                -- A number and its unit text after it ("-70 per Cycle").
                flush()
                list[#list + 1] = t.value .. " " .. nxt.value
                i = i + 1
            elseif NUMBER_NAMES[t.name] then
                flush()
                local word = NUMBER_NAMES[t.name]
                list[#list + 1] = (text.game_resource_name(word) or word) .. " " .. t.value
            elseif t.name == "Level_Text" and toks[i + 1] and toks[i + 1].kind == "text" then
                flush()
                list[#list + 1] = t.value .. " " .. toks[i + 1].value
                i = i + 1
            else
                flush()
                list[#list + 1] = t.value
            end
        end
        i = i + 1
    end
    flush()
    return list
end

-- A resource's tooltip, as the bar shows it on hover. Each resource widget
-- on the bar owns a WBP_ResourceHoverTooltip holding every kind of module;
-- the game fills it only on the first hover, so it was still a template
-- ("#ResourceName"). Which modules a resource shows is the game's own
-- list, GetResourceBP(id).TooltipModuleTypes (Deuterium: Name, Capacity,
-- Production, Description; Morale: Morale, Description), and each module
-- fills itself with SetResource_BP(id) and Update() (VM, 2026-10-19).
local MODULES = { NameModule = "Name", CapacityModule = "Capacity", ProductionModule = "Production",
    DescriptionModule = "Desc", MoraleModule = "Morale", HullModule = "Hull", PowerModule = "Energy",
    CrewModule = "Crew", ThreadModule = "ThreatLevel", BatteryModule = "Battery" }

local function find_in(root, cls)
    local W = StaticFindObject("/Script/UMG.UserWidget")
    local P = StaticFindObject("/Script/UMG.PanelWidget")
    local count = 0
    local function find(x, depth)
        if depth > 8 or count > 300 or not (x and x:IsValid()) then return nil end
        count = count + 1
        if x:GetClass():GetFName():ToString() == cls then return x end
        if x:IsA(W) then
            local tree = x.WidgetTree
            if tree and tree:IsValid() and tree.RootWidget then return find(tree.RootWidget, depth + 1) end
        elseif x:IsA(P) then
            for i = 0, x:GetChildrenCount() - 1 do
                local r = find(x:GetChildAt(i), depth + 1)
                if r then return r end
            end
        end
        return nil
    end
    return find(root, 0)
end

-- The tooltip of the bar's widget for this resource, or any bar tooltip.
-- FindAllOf does not find subclasses by the base class's name
-- (STVResourceWidget gave none), so the bar's widget classes are named.
local BAR_CLASSES = { "STVSingleResourceWidget", "WBP_HullIntegrity_C", "WBP_ThreatLevel_C",
    "WBP_AggregateEnergy_Energy_C", "WBP_AggregateEnergy_Battery_C", "WBP_Morale_03_C",
    "WBP_Crew_Resource_C", "WBP_WorkTeams_Resource_C" }

local function bar_widgets()
    local out = {}
    for _, cls in ipairs(BAR_CLASSES) do
        for _, w in ipairs(FindAllOf(cls) or {}) do out[#out + 1] = w end
    end
    return out
end

local function tooltip_for(id)
    local any = nil
    for _, w in ipairs(bar_widgets()) do
        if w:IsValid() and w:GetFullName():find("WBP_HUD", 1, true) then
            local ok, t = pcall(function() return w.HoverTooltip end)
            if ok and t and t:IsValid() then
                any = any or t
                local okr, rs = pcall(function() return w.ResourceString:ToString() end)
                if okr and rs == id then return t end
            end
        end
    end
    return any
end

function M.resource_lines(id)
    local rm = FindFirstOf("STVResourceManager")
    local E = StaticFindObject("/Script/STVoyager.ESTVResourceHoverTooltipTypes")
    local kinds = {}
    local data = nil
    pcall(function()
        data = rm:GetResourceBP(id)
        for _, v in pairs(data.TooltipModuleTypes) do
            local n = E:GetNameByValue(v:get()):ToString():gsub("^.*::", "")
            if MODULES[n] then kinds[#kinds + 1] = MODULES[n] end
        end
    end)
    if #kinds == 0 then return {} end
    local tip = tooltip_for(id)
    if not tip then return {} end
    local list = {}
    for _, kind in ipairs(kinds) do
        local m = find_in(tip, "WBP_ResourceHoverModule_" .. kind .. "_C")
        if m then
            -- The resource's own data, not an empty table: with {} the
            -- first read hung the mod (VM, 2026-10-19).
            pcall(function() m:SetResource_BP(id, data) end)
            pcall(function() m:Update() end)
            for _, line in ipairs(M.lines(m)) do list[#list + 1] = line end
        end
    end
    return list
end

-- The ship view's info panel shown now, or nil.
function M.room_panel()
    for _, p in ipairs(FindAllOf("WBP_Sideview_InfoPanel_C") or {}) do
        if p:IsValid() and screen.shown(p) then return p end
    end
    return nil
end

return M
