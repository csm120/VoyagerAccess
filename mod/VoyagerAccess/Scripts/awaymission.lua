-- Away mission team selection (WBP_AwayMissionLoadout). Read 2026-10-11 on
-- "Investigating the Array", the demo's first away mission:
--   * the hero slots are the loadout's HeroPickers (STVAwayMissionHeroPicker);
--     each slot's button is an OpenSelectionButton with only a plus picture,
--     so focus said nothing and Casey could not tell a slot was filled;
--   * a filled slot shows the hero on its HeroPlaque (HeroNameText,
--     HeroStatSheet with RankText, the skills and TraitText);
--   * Enter on a slot opens a list of WBP_AwayMissionHeroSelectionButton,
--     each with its own HeroPlaque;
--   * StartMissionButton stays collapsed until MissionInfo.HeroesNeeded
--     slots are filled (2 here, bCanStartWithFewerHeroes false);
--   * MissionTitle and MissionDescription are collapsed in this layout but
--     have the text; the challenges are WBP_AwayMissionChallengeSkills, each
--     with skill icons (AttributeDisplayN.AttributeIcon, "MI_UI_Science").

local screen = require("screen")

local M = {}

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
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

local function sentences(parts)
    local out = {}
    for i, s in ipairs(parts) do
        s = s:gsub("%.%s*$", "")
        if i < #parts and not s:find("[!?]$") then s = s .. "." end
        out[i] = s
    end
    local text = table.concat(out, " ")
    if not text:find("[!?]$") then text = text .. "." end
    return text
end

local function loadout()
    for _, w in ipairs(FindAllOf("WBP_AwayMissionLoadout_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") then return w end
    end
    return nil
end

-- "Tom Paris, level 1, Pilot. Command 21, Engineering 11, Medicine 17", or
-- nil when the plaque shows no hero.
local function plaque_text(plaque)
    if not (plaque and plaque:IsValid() and screen.shown(plaque)) then return nil end
    local name = plain(text_of(plaque.HeroNameText))
    -- An empty combat slot's plaque counts as shown with its placeholder
    -- "#Hero Name" (2026-10-14).
    if name == "" or name:sub(1, 1) == "#" then return nil end
    local head = name
    local sheet = plaque.HeroStatSheet
    if sheet and sheet:IsValid() then
        local rank = plain(text_of(sheet.HeroRank and sheet.HeroRank.RankText))
        if rank ~= "" then head = head .. ", " .. rank:lower() end
        local trait = plain(text_of(sheet.HeroTraits and sheet.HeroTraits.TraitText))
        if trait ~= "" then head = head .. ", " .. trait end
    end
    local parts = { head }
    local skills = require("rooms").skills_of(sheet)
    if skills ~= "" then parts[#parts + 1] = skills end
    -- A battle's hero list shows each hero's combat ability (AbilityName,
    -- "Maquis Maneuver"), read as "Ability, Chakotay, Lv. 1, ..." before.
    local ability = sheet and sheet:IsValid() and plain(text_of(sheet.AbilityName)) or ""
    -- In the battle list it counts as hidden although it is on screen.
    local battle = path_of(plaque):find("CombatHeroSelectionButton", 1, true) ~= nil
    if ability ~= "" and (battle or screen.shown(sheet.AbilityName)) then parts[#parts + 1] = "Ability: " .. ability end
    return sentences(parts)
end

-- A slot's button: ...WBP_AwayMissionLoadout_C_N...<picker>.WidgetTree_N.OpenSelectionButton
-- The combat hero setup (WBP_CombatHeroLoadout, native
-- STVCombatHeroLoadoutWidget) has the same HeroPickers of STVHeroPicker
-- with a HeroPlaque, read from its class 2026-10-11 before any battle was
-- reached; its slots use the same labels, not yet heard in a battle.
local LOADOUTS = { WBP_AwayMissionLoadout_C = "Away team slot", WBP_CombatHeroLoadout_C = "Combat slot" }

-- In a battle the loadout is a widget inside the combat window, named
-- HeroLoadout, so its class is not in the path (2026-10-14: the slots
-- read only "Select hero").
local COMBAT_LOADOUT = "^(.-WBP_CombatMainWidget_C_%d+%.WidgetTree_%d+%.HeroLoadout)%."

-- The battle's hero setup while it is on screen, or nil.
function M.combat_loadout()
    for _, w in ipairs(FindAllOf("WBP_CombatMainWidget_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") then
            local ok, L = pcall(function() return w.HeroLoadout end)
            if ok and L and L:IsValid() and screen.shown(L) then return L end
        end
    end
    return nil
end

-- "Prepare for combat. U.S.S. Voyager, combat power 77, against Val Jean,
-- combat power 51": the two ship panels (WBP_UI_Ship_Panel: ShipName,
-- Combat_Power), the player's first, then up to how many heroes.
function M.combat_prep_text(L)
    local prefix = path_of(L) .. "."
    local ships = {}
    for _, p in ipairs(FindAllOf("WBP_UI_Ship_Panel_C") or {}) do
        local pp = p:IsValid() and path_of(p)
        if pp and pp:sub(1, #prefix) == prefix and screen.shown(p) then
            local name = plain(text_of(p.ShipName))
            local power = plain(text_of(p.Combat_Power))
            local idx = 0
            pcall(function() idx = p:GetParent():GetChildIndex(p) end)
            if name ~= "" then
                ships[#ships + 1] = { idx = idx, text = name .. (power ~= "" and (", combat power " .. power) or "") }
            end
        end
    end
    table.sort(ships, function(a, b) return a.idx < b.idx end)
    local parts = { "Prepare for combat" }
    if #ships >= 2 then
        parts[#parts + 1] = ships[1].text .. ", against " .. ships[2].text
    elseif ships[1] then
        parts[#parts + 1] = ships[1].text
    end
    local count = 0
    pcall(function() L.HeroPickers:ForEach(function() count = count + 1 end) end)
    if count > 0 then parts[#parts + 1] = "Choose up to " .. count .. " heroes" end
    return sentences(parts)
end

local combat_prep_said = nil

local function combat_prep_poll()
    local L = M.combat_loadout()
    if not L then combat_prep_said = nil return end
    local key = path_of(L)
    if combat_prep_said == key then return end
    combat_prep_said = key
    local text = M.combat_prep_text(L)
    print("[VoyagerAccess] combat prep: " .. text .. "\n")
    require("speech").say_long(text, true)
    local okl, label = pcall(function() return require("focus").current_label() end)
    if okl and label and label ~= "" then require("speech").say(label, false) end
    require("dialogue").remember(text)
end

local function loadout_of(path)
    local cp = path:match(COMBAT_LOADOUT)
    if cp then
        local L = StaticFindObject(cp)
        if L and L:IsValid() then return L, "Combat slot" end
    end
    for cls, name in pairs(LOADOUTS) do
        local lp = path:match("^(.-" .. cls .. "_%d+)")
        if lp then
            local L = StaticFindObject(lp)
            if L and L:IsValid() then return L, name end
        end
    end
    return nil
end

function M.is_slot(path)
    return path ~= nil and path:find("%.OpenSelectionButton$") ~= nil
        and (path:find("WBP_AwayMissionLoadout_C_%d+") ~= nil or path:find("WBP_CombatHeroLoadout_C_%d+") ~= nil
            or path:match(COMBAT_LOADOUT) ~= nil)
end

function M.slot_label(path)
    local L, slot_name = loadout_of(path)
    if not L then return nil end
    local picker_path = path:match("^(.-)%.WidgetTree_%d+%.OpenSelectionButton$")
    local index, count, picker = nil, 0, nil
    L.HeroPickers:ForEach(function(i, e)
        local p = e:get()
        count = count + 1
        if p:IsValid() and path_of(p) == picker_path then index, picker = i, p end
    end)
    if not picker then return nil end
    local hero = plaque_text(picker.HeroPlaque)
    local head = string.format("%s %d of %d", slot_name, index, count)
    if hero then
        -- Once every slot is filled the game starts the mission on Enter,
        -- wherever focus is: Enter on a slot to change its hero started
        -- "Kazon in need", and choosing the last hero started Phage
        -- (VM, 2026-10-15). Said on every filled slot from then on.
        -- Every slot filled: Start Mission can show with one hero of three
        -- (Meeting the Kazon & Kes, Neelix in slot 1, VM, 2026-10-15).
        local full = true
        pcall(function()
            L.HeroPickers:ForEach(function(_, e)
                local p = e:get()
                if not (p:IsValid() and plaque_text(p.HeroPlaque)) then full = false end
            end)
        end)
        if full and path:find("WBP_AwayMissionLoadout_C", 1, true) then
            return head .. ": " .. (hero:gsub("%.?%s*$", "")) .. ". Team complete: Enter starts the mission."
        end
        return head .. ": " .. hero
    end
    return head .. ", empty. Enter to choose a hero."
end

-- Home and End on a team screen: the first slot, or Start Mission (the last
-- slot while it is hidden). Each slot's button sits in its own picker, so
-- the general Home and End, which look in the focused button's own list,
-- did nothing (full game, VM, 2026-10-14). True when it handled the key.
function M.loadout_edge(path, last)
    local L = path and loadout_of(path)
    if not L then
        -- Start Mission is the loadout's own button, not a slot.
        local lp = path and path:match("^(.-WBP_AwayMissionLoadout_C_%d+)%.WidgetTree_%d+%.StartMissionButton$")
        L = lp and StaticFindObject(lp)
        if not (L and L:IsValid()) then return false end
    end
    local pickers = {}
    pcall(function() L.HeroPickers:ForEach(function(_, e) pickers[#pickers + 1] = e:get() end) end)
    local want = nil
    if last then
        local lp = path_of(L) .. "."
        for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
            local bp = b:IsValid() and path_of(b)
            if bp and bp:sub(1, #lp) == lp and bp:find("%.StartMissionButton$") and screen.shown(b) then want = b end
        end
    end
    local picker = last and pickers[#pickers] or pickers[1]
    if not want and picker and picker:IsValid() then
        local pp = path_of(picker) .. "."
        for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
            local bp = b:IsValid() and path_of(b)
            if bp and bp:sub(1, #pp) == pp and bp:find("%.OpenSelectionButton$") then want = b end
        end
    end
    if want then want:SetFocus() end
    return true
end

-- A hero in the list a slot opens.
-- The battle's list is WBP_CombatHeroSelectionButton (seen 2026-10-14 in
-- the Val Jean test fight): a HeroPlaque with HeroNameText and a stat
-- sheet with RankText and AbilityName. WBP_SelectionButtonCombat was the
-- earlier guess from the class list.
function M.is_hero_button(path)
    return path ~= nil and (path:find("WBP_AwayMissionHeroSelectionButton_C_%d+$") ~= nil
        or path:find("WBP_SelectionButtonCombat_C_%d+$") ~= nil
        or path:find("WBP_CombatHeroSelectionButton_C_%d+$") ~= nil)
end

-- Every hero button of the away team and battle lists (shown or not).
function M.hero_buttons()
    local out = {}
    for _, cls in ipairs({ "WBP_AwayMissionHeroSelectionButton_C", "WBP_SelectionButtonCombat_C",
        "WBP_CombatHeroSelectionButton_C" }) do
        for _, h in ipairs(FindAllOf(cls) or {}) do out[#out + 1] = h end
    end
    return out
end

function M.hero_label(path)
    local b = StaticFindObject(path)
    if not (b and b:IsValid()) then return nil end
    local ok, plaque = pcall(function() return b.HeroPlaque end)
    local text = ok and plaque_text(plaque) or nil
    if not text then return nil end
    -- Its place in the list, and whether a slot already has this hero
    -- (Kes was offered with no word that she was on the team, 2026-10-14).
    local cls = path:match("([%w_]+)_C_%d+$") .. "_C"
    local shown = {}
    for _, o in ipairs(FindAllOf(cls) or {}) do
        if o:IsValid() and path_of(o):find("^/Engine/Transient%.") and screen.shown(o) then
            local slot = o.Slot
            local row, col = 0, 0
            pcall(function() row, col = slot.Row or 0, slot.Column or 0 end)
            -- Outside a grid the slot has no Row: UE4SS gave back an object.
            if type(row) ~= "number" then row = 0 end
            if type(col) ~= "number" then col = 0 end
            local idx = 0
            pcall(function() idx = o:GetParent():GetChildIndex(o) end)
            shown[#shown + 1] = { p = path_of(o), key = row * 1000 + col * 100 + idx }
        end
    end
    table.sort(shown, function(x, y) return x.key < y.key end)
    local index = nil
    for i, s in ipairs(shown) do if s.p == path then index = i end end
    local name = plain(text_of(plaque.HeroNameText))
    local L = loadout_of(path) or M.combat_loadout() or loadout()
    local on_team = false
    if L and name ~= "" then
        pcall(function()
            L.HeroPickers:ForEach(function(_, e)
                local p = e:get()
                if p:IsValid() and plain(text_of(p.HeroPlaque and p.HeroPlaque.HeroNameText)) == name
                    and screen.shown(p.HeroPlaque) then
                    on_team = true
                end
            end)
        end)
    end
    if on_team then text = text:gsub("^([^,%.]+)", "%1, on the team", 1) end
    local oke, enabled = pcall(function() return b:GetIsEnabled() end)
    -- A battle's unavailable heroes stay enabled and are drawn at half
    -- opacity (Chakotay and B'Elanna in the sparring match against their own
    -- ship; Enter did nothing and nothing said why, VM, 2026-10-14).
    local oko, op = pcall(function() return b:GetRenderOpacity() end)
    if (oke and enabled == false) or (oko and type(op) == "number" and op < 0.75) then
        text = text:gsub("^([^,%.]+)", "%1, unavailable", 1)
    end
    if index then text = text:gsub("%.$", "") .. string.format(", %d of %d.", index, #shown) end
    return text
end

-- Read when the team selection opens: the mission, how many heroes it
-- needs, what it recommends, and its challenges in screen order.
function M.window_text()
    local L = loadout()
    if not L then return "" end
    local parts = {}
    local title = plain(text_of(L.MissionTitle))
    parts[#parts + 1] = "Away mission" .. (title ~= "" and (": " .. title) or "")
    local desc = plain(text_of(L.MissionDescription))
    if desc ~= "" then parts[#parts + 1] = desc end
    local ok, needed = pcall(function() return L.MissionInfo.HeroesNeeded end)
    if ok and needed and needed > 0 then
        parts[#parts + 1] = string.format("Choose %d hero%s", needed, needed == 1 and "" or "es")
    end
    local enum = StaticFindObject("/Script/STVoyager.ESTVHeroAttribute")
    local rec = {}
    pcall(function()
        L.MissionInfo.RecommendedAttributes:ForEach(function(_, e)
            local n = enum:GetNameByValue(e:get()):ToString():gsub("^ESTVHeroAttribute::", "")
            rec[#rec + 1] = n
        end)
    end)
    if #rec > 0 then parts[#parts + 1] = "Recommended skills: " .. table.concat(rec, ", ") end
    local traits = {}
    for _, w in ipairs(FindAllOf("WBP_AwayMissionRecommendedTraits_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
            local t = plain(text_of(w.Trait))
            if t ~= "" then traits[#traits + 1] = t end
        end
    end
    if #traits > 0 then parts[#parts + 1] = "Recommended traits: " .. table.concat(traits, ", ") end
    local challenges = {}
    for _, w in ipairs(FindAllOf("WBP_AwayMissionChallengeSkills_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
            local skills = {}
            for i = 1, 3 do
                local a = w["AttributeDisplay" .. i]
                if a and a:IsValid() and screen.shown(a) then
                    local im = a.AttributeIcon
                    local ro = im and im:IsValid() and im.Brush.ResourceObject
                    local s = ro and ro:IsValid() and ro:GetFName():ToString():match("^MI_UI_(%a+)")
                    if s then skills[#skills + 1] = s end
                end
            end
            local parent = w:GetParent()
            local order = (parent and parent:IsValid()) and parent:GetChildIndex(w) or #challenges
            if #skills > 0 then challenges[#challenges + 1] = { order = order, text = table.concat(skills, ", ") } end
        end
    end
    table.sort(challenges, function(a, b) return a.order < b.order end)
    if #challenges > 0 then
        local list = {}
        for i, c in ipairs(challenges) do list[i] = i .. ": " .. c.text end
        parts[#parts + 1] = #challenges .. " challenges. " .. table.concat(list, "; ")
    end
    return sentences(parts)
end

-- The mission itself (WBP_Dialogue_Window_AwayMission with
-- WBP_Dialogue_Choice_AwayMission choices). The game offers only the mouse
-- and gamepad here and nothing takes keyboard focus, so the arrows did
-- nothing (Casey stuck, 2026-10-11). The mod walks a flat list instead,
-- as on the System Map: each choice, then its heroes, then its Confirm.
-- Read 2026-10-11 on the first mission:
--   * each choice's HeroStatus has one WBP_AwayMission_Choice_HeroSelection
--     per hero (PlaqueWidgetTemplate first), with a Button and
--     WBP_HeroAbilityIcon.AttributeValue, the hero's value in the needed
--     skill ("-" when the hero has none); they have no name text, so names
--     come from the window's HeroStatus plaques in the same order;
--   * clicking a hero's Button selects them for that choice (the choice's
--     ConfirmButton then says "Confirm" instead of "Lock In");
--   * ConfirmButton is a hold button ("[HOLD]").
local mission_items = nil   -- list built on demand; rebuilt when choices change
local mission_index = nil
local mission_sig = nil

local function choices()
    local list = {}
    for _, w in ipairs(FindAllOf("WBP_Dialogue_Choice_AwayMission_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
            list[#list + 1] = w
        end
    end
    local function order(w)
        local parent = w:GetParent()
        return (parent and parent:IsValid()) and parent:GetChildIndex(w) or 0
    end
    table.sort(list, function(a, b) return order(a) < order(b) end)
    return list
end

-- Hero widgets under prefix of the given class, template first.
local function heroes_under(prefix, cls)
    local list = {}
    for _, h in ipairs(FindAllOf(cls) or {}) do
        local p = h:IsValid() and path_of(h)
        if p and p:sub(1, #prefix + 1) == prefix .. "." and screen.shown(h) then list[#list + 1] = h end
    end
    table.sort(list, function(a, b)
        local ta, tb = path_of(a):find("PlaqueWidgetTemplate$") ~= nil, path_of(b):find("PlaqueWidgetTemplate$") ~= nil
        if ta ~= tb then return ta end
        return path_of(a) < path_of(b)
    end)
    return list
end

local function hero_names()
    local names = {}
    for _, w in ipairs(FindAllOf("WBP_Dialogue_Window_AwayMission_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
            local prefix = path_of(w)
            local plaques = {}
            for _, cls in ipairs({ "STVAwayMissionHeroSelectionPlaque" }) do
                for _, h in ipairs(FindAllOf(cls) or {}) do
                    local p = h:IsValid() and path_of(h)
                    if p and p:sub(1, #prefix + 1) == prefix .. "." and p:find("HeroStatus%.") and screen.shown(h) then
                        plaques[#plaques + 1] = h
                    end
                end
            end
            table.sort(plaques, function(a, b)
                local ta, tb = path_of(a):find("PlaqueWidgetTemplate$") ~= nil, path_of(b):find("PlaqueWidgetTemplate$") ~= nil
                if ta ~= tb then return ta end
                return path_of(a) < path_of(b)
            end)
            for i, h in ipairs(plaques) do names[i] = plain(text_of(h.HeroNameText)) end
        end
    end
    return names
end

-- A hero's trait ("Pilot", "Klingon - Innovator") from the mission
-- window's team plaques, or "".
local function trait_of(name)
    local found = ""
    pcall(function()
        for _, h in ipairs(FindAllOf("STVAwayMissionHeroSelectionPlaque") or {}) do
            if h:IsValid() and path_of(h):find("^/Engine/Transient%.") and path_of(h):find("HeroStatus%.")
                and screen.shown(h) and plain(text_of(h.HeroNameText)) == name then
                local sheet = h.HeroStatSheet
                local t = plain(text_of(sheet and sheet.HeroTraits and sheet.HeroTraits.TraitText))
                if t ~= "" then found = t end
            end
        end
    end)
    return found
end

local function build()
    local items, sig = {}, {}
    local names = hero_names()
    local cs = choices()
    for ci, c in ipairs(cs) do
        local cp = path_of(c)
        sig[#sig + 1] = cp
        items[#items + 1] = { kind = "choice", choice = cp, n = ci, of = #cs }
        for hi, h in ipairs(heroes_under(cp, "WBP_AwayMission_Choice_HeroSelection_C")) do
            items[#items + 1] = { kind = "hero", choice = cp, hero = path_of(h), name = names[hi] or ("Hero " .. hi) }
        end
        items[#items + 1] = { kind = "confirm", choice = cp }
    end
    return items, table.concat(sig, "|")
end

function M.mission_active()
    return #choices() > 0
end

-- The arrows and Enter go to the choices only while the pause menu is not
-- over them: both the pause menu and the choices moved on one Down (VM,
-- 2026-10-15).
function M.keys_active()
    if not M.mission_active() then return false end
    for _, w in ipairs(FindAllOf("WBP_PauseMenu_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then return false end
    end
    return true
end

local function choice_skill(c)
    local skill = "skill"
    pcall(function()
        local ro = c.AttributeImage.Brush.ResourceObject
        if ro and ro:IsValid() then skill = ro:GetFName():ToString():match("^MI_UI_(%a+)") or skill end
    end)
    return skill, plain(text_of(c.AttributeAmount))
end

-- The active choice is the one whose button says "Confirm"; the others say
-- "Lock In". Each choice keeps a hero marked (SelectedStateWidget) even
-- when it is not the active one (read 2026-10-11).
-- A hero in the choice's team. SelectedStateWidget marks only the hero
-- clicked last; with two chosen, Kes and Tuvok went (Skill 35) while only
-- Tuvok was marked and Confirm named only him. A hero already in the team
-- shows LockedWidget (VM, 2026-10-14), so either counts.
local function chosen(h)
    local yes = false
    pcall(function()
        for _, k in ipairs({ "SelectedStateWidget", "LockedWidget" }) do
            local w = h[k]
            if w and w:IsValid() and screen.shown(w) then yes = true end
        end
    end)
    return yes
end

local function is_active(c)
    local cb = c.ConfirmButton
    return plain(text_of(cb and cb.Name_TextBlock)):lower() == "confirm"
end

-- Names of the fatigued heroes in the away mission window at path: its
-- HeroStatus_Choices plaques show "Fatigued" in the same hero order as
-- HeroStatus.
local function fatigued(window)
    local names = hero_names()
    local tired = {}
    if not window then
        -- A choice's path does not run through the window: find it.
        for _, w in ipairs(FindAllOf("WBP_Dialogue_Window_AwayMission_C") or {}) do
            if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then window = path_of(w) end
        end
    end
    if not window then return tired end
    local plaques = {}
    for _, h in ipairs(FindAllOf("STVAwayMissionHeroSelectionPlaque") or {}) do
        local hp = h:IsValid() and path_of(h)
        if hp and hp:find(window .. ".", 1, true) == 1 and hp:find("HeroStatus_Choices%.") and screen.shown(h) then
            plaques[#plaques + 1] = h
        end
    end
    table.sort(plaques, function(a, b)
        local ta, tb = path_of(a):find("PlaqueWidgetTemplate$") ~= nil, path_of(b):find("PlaqueWidgetTemplate$") ~= nil
        if ta ~= tb then return ta end
        return path_of(a) < path_of(b)
    end)
    for i, h in ipairs(plaques) do
        local hp = path_of(h) .. "."
        for _, t in ipairs(FindAllOf("TextBlock") or {}) do
            local tp = t:IsValid() and path_of(t)
            if tp and tp:sub(1, #hp) == hp and screen.shown(t) and plain(text_of(t)) == "Fatigued" then
                tired[#tired + 1] = names[i] or ("Hero " .. i)
            end
        end
    end
    return tired
end

-- "15 science points" from a choice's reward widgets
-- (WBP_ResourceReward_AwayMissionChoice: the same amount text and icon as
-- the results' rewards). A sighted player sees "+15" with an icon beside
-- each choice; it was not read (2026-10-14).
local function choice_rewards(choice_path, cls)
    local out = {}
    for _, w in ipairs(FindAllOf(cls or "WBP_ResourceReward_AwayMissionChoice_C") or {}) do
        local wp = w:IsValid() and path_of(w)
        if wp and (choice_path == "" or wp:sub(1, #choice_path + 1) == choice_path .. ".") and screen.shown(w) then
            local amount = ""
            pcall(function() amount = plain(text_of(w.ResourceAmountTextBlock)):gsub("^%+", "") end)
            -- The mission summary's reward names it ResourceAmount.
            if amount == "" then pcall(function() amount = plain(text_of(w.ResourceAmount)):gsub("^%+", "") end) end
            local res = "resources"
            pcall(function()
                local ro = w.ResourceImage.Brush.ResourceObject
                if ro and ro:IsValid() then res = ro:GetFName():ToString():match("^MI_UI_(%a+)") or res end
            end)
            res = res:gsub("(%l)(%u)", "%1 %2"):lower()
            if amount ~= "" then out[#out + 1] = amount .. " " .. res end
        end
    end
    return table.concat(out, ", ")
end

local function item_label(it)
    local c = StaticFindObject(it.choice)
    if not (c and c:IsValid()) then return nil end
    if it.kind == "choice" then
        local label = require("dialogue").away_choice_label(c) or "Choice"
        local ok, reward = pcall(choice_rewards, it.choice)
        if ok and reward ~= "" then label = label:gsub("%.?%s*$", "") .. ". Reward: " .. reward .. "." end
        -- Danger: three WBP_AwayyMission_RiskIndicator per choice, each
        -- showing its Risk image or its noRisk image; the Risk ones lit are
        -- the danger level. Read 2026-10-14 when the game's tutorial said
        -- failing a dangerous approach can injure or kill (the old note
        -- that risk could not be read looked only at the indicators'
        -- own visibility).
        local level = 0
        pcall(function()
            local prefix = it.choice .. "."
            for _, x in ipairs(FindAllOf("Image") or {}) do
                local xp = x:IsValid() and path_of(x)
                if xp and xp:sub(1, #prefix) == prefix and xp:find("riskLvl_%d") and xp:match("%.Risk$")
                    and screen.shown(x) then
                    level = level + 1
                end
            end
        end)
        if level > 0 then label = label:gsub("%.?%s*$", "") .. ". Danger level " .. level .. " of 3." end
        return string.format("Choice %d of %d: %s", it.n, it.of, label)
    elseif it.kind == "hero" then
        local h = StaticFindObject(it.hero)
        if not (h and h:IsValid()) then return nil end
        local skill, needed = choice_skill(c)
        local value = plain(text_of(h.WBP_HeroAbilityIcon and h.WBP_HeroAbilityIcon.AttributeValue))
        local text = it.name .. ", " .. ((value == "" or value == "-") and ("no " .. skill)
            or (skill .. " " .. value .. (needed ~= "" and (" of " .. needed .. " needed") or "")))
        -- "Engineering 21 of 15 needed" read as a shortfall (2026-10-14).
        local v, n = tonumber(value), tonumber(needed)
        if v and n and v >= n then text = it.name .. ", " .. skill .. " " .. value .. ", " .. needed .. " needed, enough" end
        -- Tired heroes show "Fatigued" over their portrait and lower
        -- values; say it with the hero (2026-10-14).
        local okf, tired = pcall(fatigued, it.choice:match("^(.-WBP_Dialogue_Window_AwayMission_C_%d+)"))
        if okf then
            for _, n in ipairs(tired) do if n == it.name then text = text .. ", fatigued" end end
        end
        -- A choice that asks for a trait ("Trait: Pilot") helps the hero who
        -- has it; nothing on the hero said so (Investigating the Array,
        -- VM, 2026-10-15).
        pcall(function()
            local want = (require("dialogue").away_choice_label(c) or ""):match("Trait: ([^%.]+)")
            local has = trait_of(it.name)
            if want and has ~= "" and has:lower():find(want:lower(), 1, true) then
                text = text .. ", has the " .. want .. " trait"
            end
        end)
        if is_active(c) and chosen(h) then text = text .. ", selected" end
        return text .. "."
    else
        -- Casey pressed Enter on the inactive choice's Lock In and nothing
        -- happened (2026-10-11). So say who it confirms, or that a hero must
        -- be picked for this choice first.
        if not is_active(c) then return "Lock In: select a hero for this choice first." end
        -- Several heroes can go together; only the last was named (2026-10-14:
        -- "Confirm with Tom Paris" sent Harry Kim too).
        local who = {}
        for _, o in ipairs(mission_items or {}) do
            if o.kind == "hero" and o.choice == it.choice then
                local h = StaticFindObject(o.hero)
                if h and h:IsValid() and chosen(h) then who[#who + 1] = o.name end
            end
        end
        if #who == 0 then return "Lock In: select a hero for this choice first." end
        local names = #who == 1 and who[1] or (table.concat(who, ", ", 1, #who - 1) .. " and " .. who[#who])
        return "Confirm with " .. names .. "."
    end
end

-- The game's own keyboard focus follows the mod's list. It stayed on a
-- hero the game had marked (Tuvok), the game took the same Enter and pressed
-- him, and the mod's choice of Harry Kim was lost: "Confirm with Tuvok",
-- Skill 0 (VM, 2026-10-14).
local function focus_item(it)
    pcall(function()
        local c = StaticFindObject(it.choice)
        if not (c and c:IsValid()) then return end
        local target = nil
        if it.kind == "hero" then
            local h = StaticFindObject(it.hero)
            target = h and h:IsValid() and h.Button
        elseif it.kind == "choice" then
            target = c.RightButton
        else
            target = c.ConfirmButton
        end
        if target and target:IsValid() then target:SetFocus() end
    end)
end

local function say_item()
    local it = mission_items[mission_index]
    if it then focus_item(it) end
    local label = it and item_label(it)
    if label then
        print("[VoyagerAccess] mission: " .. label .. "\n")
        require("speech").say(label, true)
    end
end

local function refresh()
    local items, sig = build()
    if sig ~= mission_sig then
        mission_items, mission_sig, mission_index = items, sig, 1
        return true
    end
    mission_items = items
    return false
end

-- For L (where am I): the item the arrows are on.
function M.mission_where()
    refresh()
    local it = mission_items[mission_index or 1]
    return it and item_label(it) or nil
end

function M.mission_step(dir)
    refresh()
    if #mission_items == 0 then return end
    local i = (mission_index or 1) + dir
    if mission_items[i] then mission_index = i end
    say_item()
end

function M.mission_edge(last)
    refresh()
    if #mission_items == 0 then return end
    mission_index = last and #mission_items or 1
    say_item()
end

local function press(b)
    b:HandleButtonPressed()
    b:HandleButtonReleased()
    b:HandleButtonClicked()
end

function M.mission_enter()
    refresh()
    local it = mission_items[mission_index or 1]
    if not it then return end
    if it.kind == "choice" then
        say_item()
    elseif it.kind == "hero" then
        local h = StaticFindObject(it.hero)
        if h and h:IsValid() and h.Button and h.Button:IsValid() then
            -- A second Enter on a hero already chosen left the highlight on
            -- Tom Paris while the game sent Harry Kim, and Confirm named Tom
            -- (VM, 2026-10-14). Choosing another hero replaces the choice,
            -- so a chosen hero is not pressed again.
            -- Heroes can now be stacked on one challenge, and a chosen one
            -- could not be taken back off ("Neelix is already chosen for
            -- this", VM, 2026-10-15): Enter presses it again (the game
            -- toggles it), and the hero is said with its new state.
            print("[VoyagerAccess] mission: select " .. it.name .. "\n")
            press(h.Button)
            -- Picked, the hero is said with where to go next.
            ExecuteInGameThreadWithDelay(600, function()
                pcall(function()
                    local cur = mission_items[mission_index]
                    local label = cur and item_label(cur)
                    if not label then return end
                    if label:find(", selected%.$") then label = label .. " Confirm is after the heroes." end
                    require("speech").say(label, true)
                end)
            end)
        end
    else
        -- A hold button: press, wait out the hold, then release. Untested
        -- (2026-10-11): if the hold does not complete, the log says so.
        local c = StaticFindObject(it.choice)
        local cb = c and c:IsValid() and c.ConfirmButton
        if not (cb and cb:IsValid()) then return end
        local label = item_label(it) or ""
        if label:find("first%.$") then
            require("speech").say(label, true)
            return
        end
        print("[VoyagerAccess] mission: confirm " .. it.choice:match("([^%.]+)$") .. "\n")
        require("speech").say("Confirming", true)
        cb:HandleButtonPressed()
        local path = path_of(cb)
        ExecuteInGameThreadWithDelay(2500, function()
            pcall(function()
                local b = StaticFindObject(path)
                if b and b:IsValid() then
                    b:HandleButtonReleased()
                    print("[VoyagerAccess] mission: confirm released\n")
                end
            end)
        end)
    end
end

function M.install()
    LoopInGameThreadWithDelay(300, function()
        local ok, err = pcall(M.mission_poll)
        if not ok then print("[VoyagerAccess] mission error: " .. tostring(err) .. "\n") end
    end)
end

-- A challenge's result (WBP_AwayMission_ChallengeResult inside the mission
-- window, read 2026-10-11): MissionResult_Text ("Failure"), HeroValueText
-- and RequiredValueText (24 of 33), and DialogueTypewriterText with the
-- story of what happened (its TargetText has the whole text at once). The
-- panel is in the window from the start with placeholder text, so it is
-- read only while shown and only when the story changes.
local last_result = nil

local function result_poll()
    for _, r in ipairs(FindAllOf("WBP_AwayMission_ChallengeResult_C") or {}) do
        local rp = r:IsValid() and path_of(r)
        if rp and rp:find("^/Engine/Transient%.") and screen.shown(r) then
            local story = ""
            pcall(function() story = plain(r.DialogueTypewriterText.TargetText:ToString()) end)
            if story == "" then story = plain(text_of(r.DialogueTypewriterText)) end
            local outcome = plain(text_of(r.MissionResult_Text))
            if story ~= "" and not story:find("Lorem ipsum", 1, true) and story ~= last_result then
                last_result = story
                local parts = {}
                if outcome ~= "" then parts[#parts + 1] = outcome end
                local have, need = plain(text_of(r.HeroValueText)), plain(text_of(r.RequiredValueText))
                -- "42 of 25" read as a fraction (2026-10-14); worded like
                -- the hero lines ("Engineering 42, 25 needed").
                if have:match("^%d+$") and need:match("^%d+$") then parts[#parts + 1] = "Skill " .. have .. ", " .. need .. " needed" end
                parts[#parts + 1] = story
                -- Rewards: WBP_ResourceReward_AwayMissionChallengeResult,
                -- amount text and an icon naming the resource
                -- ("MI_UI_SciencePoints_white"), read 2026-10-11.
                local rewards = {}
                for _, w in ipairs(FindAllOf("WBP_ResourceReward_AwayMissionChallengeResult_C") or {}) do
                    local wp = w:IsValid() and path_of(w)
                    if wp and wp:sub(1, #rp + 1) == rp .. "." and screen.shown(w) then
                        local amount = plain(text_of(w.ResourceAmountTextBlock)):gsub("^%+", "")
                        local res = "resources"
                        pcall(function()
                            local ro = w.ResourceImage.Brush.ResourceObject
                            if ro and ro:IsValid() then
                                res = ro:GetFName():ToString():match("^MI_UI_(%a+)") or res
                            end
                        end)
                        res = res:gsub("(%l)(%u)", "%1 %2"):lower()
                        if amount ~= "" then rewards[#rewards + 1] = amount .. " " .. res end
                    end
                end
                if #rewards > 0 then parts[#parts + 1] = "Reward: " .. table.concat(rewards, ", ") end
                -- Fatigue: the window's HeroStatus_Choices plaques show
                -- "Fatigued" in the same hero order as HeroStatus.
                local tired = fatigued(rp:match("^(.-WBP_Dialogue_Window_AwayMission_C_%d+)"))
                -- "Neelix, Tuvok and Chakotay", not "Neelix and Tuvok and Chakotay".
                if #tired > 0 then
                    local names = #tired == 1 and tired[1]
                        or (table.concat(tired, ", ", 1, #tired - 1) .. " and " .. tired[#tired])
                    parts[#parts + 1] = names .. (#tired == 1 and " is" or " are") .. " fatigued"
                end
                local text = sentences(parts)
                print("[VoyagerAccess] mission result: " .. text .. "\n")
                require("speech").say_long(text)
                require("dialogue").remember(text)
                -- "+150" deuterium showed on screen but was not in the
                -- result that was read (2026-10-14): the reward can appear
                -- after the text. Look again, anywhere on screen.
                -- Once a second for up to 15: the reward shows after the story
                -- text has typed out, 6 s was too short for a long one.
                if #rewards == 0 then
                    local function look(tries)
                        local done = false
                        pcall(function()
                            local late = choice_rewards(rp, "WBP_ResourceReward_AwayMissionChallengeResult_C")
                            if late == "" then late = choice_rewards("", "WBP_ResourceReward_AwayMissionChallengeResult_C") end
                            if late ~= "" then
                                done = true
                                print("[VoyagerAccess] mission result reward: " .. late .. "\n")
                                require("speech").say("Reward: " .. late, false)
                                require("dialogue").remember(text .. " Reward: " .. late .. ".")
                            end
                        end)
                        if not done and tries > 1 then
                            ExecuteInGameThreadWithDelay(1000, function() look(tries - 1) end)
                        end
                    end
                    ExecuteInGameThreadWithDelay(1000, function() look(15) end)
                end
            end
            return
        end
    end
end

-- The end of a mission (WBP_AwayMissionOutcome in the window's
-- DialogueConsequences, read 2026-10-11): rows of WBP_AwayMissionOutcomeRow
-- (DescriptionText, ValueText) in their panel's order, then one
-- WBP_AwayMissionHeroOutcome per hero (NewLevelText, levelDisplay "50/450")
-- in the window's hero order. FindAllOf returned them in reverse.
function M.outcome_text(path)
    local function order(w)
        local parent = w:GetParent()
        return (parent and parent:IsValid()) and parent:GetChildIndex(w) or 0
    end
    local function under(cls)
        local list = {}
        for _, w in ipairs(FindAllOf(cls) or {}) do
            local p = w:IsValid() and path_of(w)
            if p and p:sub(1, #path + 1) == path .. "." and screen.shown(w) then list[#list + 1] = w end
        end
        return list
    end
    local parts = { "Mission complete" }
    local rows = under("WBP_AwayMissionOutcomeRow_C")
    table.sort(rows, function(a, b) return order(a) < order(b) end)
    local exp = {}
    for _, r in ipairs(rows) do
        local d, v = plain(text_of(r.DescriptionText)), plain(text_of(r.ValueText))
        if d ~= "" then exp[#exp + 1] = d .. (v ~= "" and (" " .. v) or "") end
    end
    -- The REWARDS box above the experience (350 deuterium), not read before
    -- (2026-10-14).
    -- It sits beside the outcome widget, in the same widget tree.
    local okr, reward = pcall(choice_rewards, path:match("^(.*)%.[^%.]+$") or path, "WBP_AwayMission_Consequences_ResourceReward_C")
    if okr and reward ~= "" then parts[#parts + 1] = "Rewards: " .. reward end
    if #exp > 0 then parts[#parts + 1] = "Experience: " .. table.concat(exp, ", ") end
    local heroes = under("WBP_AwayMissionHeroOutcome_C")
    table.sort(heroes, function(a, b) return path_of(a) < path_of(b) end)
    local names = hero_names()
    for i, h in ipairs(heroes) do
        local rank, xp = plain(text_of(h.NewLevelText)), plain(text_of(h.levelDisplay))
        local line = (names[i] or ("Hero " .. i)) .. ": rank " .. rank
        local have, need = xp:match("^(%d+)/(%d+)$")
        if have then line = line .. ", " .. have .. " of " .. need .. " experience to the next rank" end
        parts[#parts + 1] = line
    end
    return sentences(parts)
end

-- How a choice is made, said once per game session after the first
-- choice: a forum player was stuck on the first mission's "Look for any
-- footprints" with a hero picked, and below the skill needed (2026-10-15).
local hinted = false
local HINT = "To choose: Down to a hero and press Enter, then Down to Confirm and press Enter. "
    .. "A hero below the skill needed can still succeed, with less chance."

-- When a new set of choices comes up, read the first one.
function M.mission_poll()
    result_poll()
    pcall(combat_prep_poll)
    if not M.mission_active() then
        mission_sig = nil
        return
    end
    if refresh() then
        local it = mission_items[1]
        local label = it and item_label(it)
        if label then
            print("[VoyagerAccess] mission: " .. label .. "\n")
            require("speech").say(label, false)
            if not hinted and it.kind == "choice" then
                hinted = true
                require("speech").say(HINT, false)
            end
        end
    end
end

return M
