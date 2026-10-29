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

-- The one on screen: the previous mission's team screen is kept hidden, and
-- the Borg cube's team selection was read with Hanon IV's text and
-- recommended skills (campaign sector 6, VM, 2026-10-17).
local function loadout()
    local first = nil
    for _, w in ipairs(FindAllOf("WBP_AwayMissionLoadout_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") then
            if screen.shown(w) then return w end
            first = first or w
        end
    end
    return first
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
    -- "Injured" or "Severely Injured" over the portrait (HeroRoomText); not
    -- said before, so an injured hero seemed fit (VM, 2026-10-17).
    pcall(function()
        local st = plaque.HeroRoomText
        if st and st:IsValid() and screen.shown(st) then
            local s = plain(text_of(st))
            if s ~= "" and s:sub(1, 1) ~= "#" then head = head .. ", " .. require("tr").lower(s) end
        end
    end)
    local sheet = plaque.HeroStatSheet
    if sheet and sheet:IsValid() then
        local rank = plain(text_of(sheet.HeroRank and sheet.HeroRank.RankText))
        if rank ~= "" then head = head .. ", " .. require("tr").lower(rank) end
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
    -- The screens combat.lua knows from the game making them: a search of
    -- every object for them ran twice a second all game long (2026-10-25).
    for _, w in ipairs(require("combat").screens()) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") then
            local ok, L = pcall(function() return w.HeroLoadout end)
            if ok and L and L:IsValid() and screen.shown(L) then return L end
        end
    end
    return nil
end

-- A hero slot on screen: its picker can count as shown while its
-- OpenSelectionButton is hidden (a battle's third slot, VM, 2026-10-15).
local function slot_shown(p)
    if not (p and p:IsValid() and screen.shown(p)) then return false end
    local ok, b = pcall(function() return p.OpenSelectionButton end)
    if ok and b and b:IsValid() then return screen.shown(b) end
    return true
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
            local idx, side = 0, 0
            pcall(function()
                local parent = p:GetParent()
                idx = parent:GetChildIndex(p)
                -- AllyGridPanel and EnemyGridPanel: a second enemy, the Kazon
                -- Swarm Alpha, was left out (Q Trials ambush, VM, 2026-10-15).
                if parent:GetFName():ToString():find("Enemy", 1, true) then side = 1 end
            end)
            if name ~= "" then
                ships[#ships + 1] = { idx = idx, side = side, text = name .. (power ~= "" and (", combat power " .. power) or "") }
            end
        end
    end
    table.sort(ships, function(a, b)
        if a.side ~= b.side then return a.side < b.side end
        return a.idx < b.idx
    end)
    local parts = { "Prepare for combat" }
    local ours, theirs = {}, {}
    for _, s in ipairs(ships) do
        if s.side == 1 then theirs[#theirs + 1] = s.text else ours[#ours + 1] = s.text end
    end
    if #theirs == 0 and #ours >= 2 then theirs = { table.remove(ours) } end
    if #ours > 0 then
        parts[#parts + 1] = table.concat(ours, "; ") .. (#theirs > 0 and (", against " .. table.concat(theirs, "; ")) or "")
    end
    local count = 0
    -- Only slots on screen: with two heroes free the third slot is hidden,
    -- and "Choose up to 3 heroes" sent focus onto it (VM, 2026-10-15).
    pcall(function() L.HeroPickers:ForEach(function(_, e)
        local ok, shown = pcall(function() return slot_shown(e:get()) end)
        if not ok or shown then count = count + 1 end
    end) end)
    if count > 0 then parts[#parts + 1] = "Choose up to " .. count .. (count == 1 and " hero" or " heroes") end
    -- Surrender and Use Cloaking can be greyed out, and the arrows skip
    -- them, so they went unmentioned; a battle with no surrender can end
    -- the game (Kazon ambush, sector 4, VM, 2026-10-16).
    local off = {}
    for _, want in ipairs({ { "SurrenderButton", "Surrender" }, { "UseCloakButton", "Use Cloaking" } }) do
        for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
            local bp = b:IsValid() and path_of(b)
            if bp and bp:sub(1, #prefix) == prefix and bp:find("%." .. want[1] .. "$") and screen.shown(b) then
                local ok, en = pcall(function() return b:GetIsEnabled() end)
                if ok and en == false then off[#off + 1] = want[2] end
            end
        end
    end
    if #off > 0 then parts[#parts + 1] = "Not available: " .. table.concat(off, ", ") end
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
    -- The battle result's SetDamageSummary hook, again: tried when the result
    -- class first appears, at the main menu, it did not register, and an
    -- Auto Resolve result stayed silent until a key (Q Trial, VM,
    -- 2026-10-22). By the setup it registers.
    pcall(function() require("popups").ensure_damage_hook() end)
    require("speech").say_long(text, true)
    local okl, label = pcall(function() return require("focus").current_label() end)
    if okl and label and label ~= "" then require("speech").say(label, false) end
    require("dialogue").remember(text)
end

-- True while focus is in a battle setup whose "Prepare for combat" has not
-- been said: focus.lua holds the slot, which the setup's reading says after
-- it ("Combat slot 1 of 3, empty" came before and after it, demo, VM,
-- 2026-10-22).
function M.combat_prep_pending(path)
    local cp = path and path:match(COMBAT_LOADOUT)
    return cp ~= nil and combat_prep_said ~= cp
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
    -- Hidden slots are not counted: a battle's third slot hides when no
    -- hero is left for it (VM, 2026-10-15).
    L.HeroPickers:ForEach(function(_, e)
        local p = e:get()
        if slot_shown(p) then
            count = count + 1
            if path_of(p) == picker_path then index, picker = count, p end
        end
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
        -- Superseded: Enter on a filled slot now opens its hero list again,
        -- and only Start Mission starts (player report, 0.3.82, 2026-10-24),
        -- so the hint names the way there. Under a new hint key: anyone who
        -- had heard the old one twice would never have heard this one.
        local full = true
        pcall(function()
            L.HeroPickers:ForEach(function(_, e)
                local p = e:get()
                if slot_shown(p) and not plaque_text(p.HeroPlaque) then full = false end
            end)
        end)
        if full and path:find("WBP_AwayMissionLoadout_C", 1, true) then
            return head .. ": " .. (hero:gsub("%.?%s*$", "")) .. ". Team complete" .. require("hints").text("team_end", ": End moves to Start Mission") .. "."
        end
        return head .. ": " .. hero
    end
    return head .. ", empty" .. require("hints").text("slot_enter", ". Enter to choose a hero") .. "."
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
            -- The battle's Start Combat is its ProceedButton: End stopped on
            -- slot 3 (VM, 2026-10-16).
            if bp and bp:sub(1, #lp) == lp and (bp:find("%.StartMissionButton$") or bp:find("%.ProceedButton$"))
                and screen.shown(b) then want = b end
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

-- Why a hero cannot go, from the hero manager's conditions
-- (ESTVCrewMemberCondition; DoesHeroHaveCondition and
-- GetHeroRemainingRecoveryCycles take the hero's id, the button's
-- CurrentCharacter). Every hero in a battle's list was "unavailable" with no
-- reason: Chakotay severely injured for 20 cycles, Harry Kim away (full
-- game, sector 7, 2026-10-18). Recruited (7) and Quarterless (5) block
-- nothing and are left out.
local CONDITIONS = { { 8, "dead" }, { 9, "left behind" }, { 2, "gravely sick" }, { 1, "sick" },
    { 4, "severely injured" }, { 3, "injured" }, { 11, "fatigued" }, { 10, "busy" }, { 6, "away" } }

function M.hero_condition(id)
    local m = FindFirstOf("STVHeroManager")
    if not (m and m:IsValid() and id) then return nil end
    local out = {}
    for _, c in ipairs(CONDITIONS) do
        local ok, has = pcall(function() return m:DoesHeroHaveCondition(id, c[1]) end)
        if ok and has == true then
            local okc, n = pcall(function() return m:GetHeroRemainingRecoveryCycles(id, c[1]) end)
            -- "away" counts 1 whatever the mission's length, so no number there.
            -- tr.word: dead | sick | busy | away
            local word = require("tr").word(c[2])
            if okc and type(n) == "number" and n > 1 and c[1] ~= 6 then
                out[#out + 1] = string.format("%s, %d cycles", word, n)
            else
                out[#out + 1] = word
            end
        end
    end
    return #out > 0 and table.concat(out, ", ") or nil
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
    local okid, id = pcall(function() return b.CurrentCharacter end)
    local cond = okid and type(id) == "userdata" and M.hero_condition(id) or nil
    -- The plaque can show the condition itself: "Joe Carey, injured, 10
    -- cycles, injured, level 10" (VM, 2026-10-18). Keep only the mod's,
    -- which has the cycles.
    if cond then
        local word = cond:match("^([%a ]+)")
        if word then text = (text:gsub(", " .. word .. "([,%.])", "%1", 1)) end
    end
    if (oke and enabled == false) or (oko and type(op) == "number" and op < 0.75) then
        text = text:gsub("^([^,%.]+)", "%1, unavailable" .. (cond and (": " .. cond) or ""), 1)
    elseif cond then
        text = text:gsub("^([^,%.]+)", "%1, " .. cond, 1)
    end
    if index then text = text:gsub("%.$", "") .. string.format(", %d of %d.", index, #shown) end
    return text
end

-- What the team selection recommends and its challenges, in screen order:
-- { rec = skill names, traits = trait texts, challenges = skill lists }.
local function briefing(L)
    local enum = StaticFindObject("/Script/STVoyager.ESTVHeroAttribute")
    local rec = {}
    pcall(function()
        L.MissionInfo.RecommendedAttributes:ForEach(function(_, e)
            local n = enum:GetNameByValue(e:get()):ToString():gsub("^ESTVHeroAttribute::", "")
            rec[#rec + 1] = require("text").hero_attribute_name(e:get()) or n
        end)
    end)
    local function order(w)
        local parent = w:GetParent()
        return (parent and parent:IsValid()) and parent:GetChildIndex(w) or 0
    end
    local traits = {}
    for _, w in ipairs(FindAllOf("WBP_AwayMissionRecommendedTraits_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
            local t = plain(text_of(w.Trait))
            if t ~= "" then traits[#traits + 1] = { order = order(w), text = t } end
        end
    end
    -- In the panel's order: FindAllOf can give widgets in reverse.
    table.sort(traits, function(a, b) return a.order < b.order end)
    for i, t in ipairs(traits) do traits[i] = t.text end
    local challenges = {}
    for _, w in ipairs(FindAllOf("WBP_AwayMissionChallengeSkills_C") or {}) do
        if w:IsValid() and path_of(w):find("^/Engine/Transient%.") and screen.shown(w) then
            local skills = {}
            for i = 1, 3 do
                local a = w["AttributeDisplay" .. i]
                if a and a:IsValid() and screen.shown(a) then
                    local im = a.AttributeIcon
                    local ro = im and im:IsValid() and im.Brush.ResourceObject
                    local s = ro and ro:IsValid() and require("text").skill_icon_name(ro:GetFName():ToString())
                    if s then skills[#skills + 1] = s end
                end
            end
            if #skills > 0 then challenges[#challenges + 1] = { order = order(w), text = table.concat(skills, ", ") } end
        end
    end
    table.sort(challenges, function(a, b) return a.order < b.order end)
    for i, c in ipairs(challenges) do challenges[i] = c.text end
    return { rec = rec, traits = traits, challenges = challenges }
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
    local b = briefing(L)
    if #b.rec > 0 then parts[#parts + 1] = "Recommended skills: " .. table.concat(b.rec, ", ") end
    if #b.traits > 0 then parts[#parts + 1] = "Recommended traits: " .. table.concat(b.traits, ", ") end
    if #b.challenges > 0 then
        local list = {}
        for i, c in ipairs(b.challenges) do list[i] = i .. ": " .. c end
        parts[#parts + 1] = #b.challenges .. " challenges. " .. table.concat(list, "; ")
    end
    if #b.rec + #b.traits + #b.challenges > 0 then
        local hint = require("hints").text("briefing_up", "Up from the first slot goes through the recommendations and challenges one at a time")
        if hint ~= "" then parts[#parts + 1] = hint end
    end
    return sentences(parts)
end

-- The same recommendations and challenges as lines above the first slot:
-- the screen shows each trait and each challenge as its own box, and the
-- opening text said them once only (firefly82's review, 2026-10-24). Up
-- from the first slot goes into them, Up and Down move, Home goes to the
-- first, and Down from the last (or End) goes back to the slots. The game
-- keeps its focus on the first slot meanwhile; the game's own Down would
-- move it to slot 2, so the mod puts it back without saying it. Any other
-- key leaves the lines.
local function briefing_lines(L)
    local b = briefing(L)
    local lines = {}
    if #b.rec > 0 then lines[#lines + 1] = "Recommended skills: " .. table.concat(b.rec, ", ") .. "." end
    for _, t in ipairs(b.traits) do lines[#lines + 1] = require("tr").fill("Recommended trait: {s}", t) .. "." end
    for i, c in ipairs(b.challenges) do
        lines[#lines + 1] = string.format("Challenge %d of %d: %s.", i, #b.challenges, c)
    end
    return lines
end

local brief = nil   -- { anchor = first slot's path, index = line, keys = key count }

-- The away team's first shown slot button and its loadout, if path is it.
local function first_slot(path)
    if not (path and M.is_slot(path) and path:find("WBP_AwayMissionLoadout_C_%d+")) then return nil end
    local L = loadout_of(path)
    if not L then return nil end
    local first = nil
    pcall(function()
        L.HeroPickers:ForEach(function(_, e)
            local p = e:get()
            if not first and slot_shown(p) then first = p end
        end)
    end)
    local b = first and first.OpenSelectionButton
    if b and b:IsValid() and path_of(b) == path then return L, b end
    return nil
end

local function hold_anchor(b)
    local f = require("focus")
    f.hush_focus_until = os.clock() + 0.5
    pcall(function() b:SetFocus() end)
    local p = path_of(b)
    ExecuteInGameThread(function()
        pcall(function()
            local nb = StaticFindObject(p)
            if nb and nb:IsValid() then nb:SetFocus() end
        end)
    end)
end

-- Up (dir -1) or Down (1) on the team selection; true when it handled the key.
-- A mod list open over the team selection (F1, Ctrl+F1, What's new, N, C,
-- the ship's room list) has the arrows, not the briefing lines: they are
-- asked for before those lists in focus.lua (Fable review, 2026-10-24).
function M.mod_list_open()
    for _, m in ipairs({ "whatsnew", "hotkeys", "credits", "help" }) do
        local ok, open = pcall(function() local x = require(m) return x.open and x.open() end)
        if ok and open then return true end
    end
    local ok, open = pcall(function()
        return require("ship").list_open() or require("resources").list_open() or require("view").nav_open()
    end)
    return ok and open and true or false
end

function M.briefing_step(path, dir)
    if M.mod_list_open() then return false end
    local count = require("keys").key_count or 0
    if brief and (brief.anchor ~= path or count ~= brief.keys + 1) then brief = nil end
    if not brief and dir > 0 then return false end
    local L, b = first_slot(path)
    if not L then brief = nil return false end
    local lines = briefing_lines(L)
    if #lines == 0 then brief = nil return false end
    local i
    if not brief then
        i = #lines
        brief = { anchor = path }
    else
        i = math.max(1, (brief.index or #lines) + dir)
    end
    hold_anchor(b)
    if i > #lines then
        brief = nil
        local label = M.slot_label(path)
        if label then require("speech").say(label, true) end
        return true
    end
    brief.index, brief.keys = i, count
    print("[VoyagerAccess] briefing: " .. lines[i] .. "\n")
    require("speech").say(lines[i], true)
    return true
end

-- Home and End while on the lines: Home the first line, End back to the
-- slots' own End (Start Mission or the last slot). True when handled.
function M.briefing_edge(path, last)
    local count = require("keys").key_count or 0
    if not (brief and brief.anchor == path and count == brief.keys + 1) then
        brief = nil
        return false
    end
    if last then brief = nil return false end
    local L, b = first_slot(path)
    if not L then brief = nil return false end
    local lines = briefing_lines(L)
    if #lines == 0 then brief = nil return false end
    brief.index, brief.keys = 1, count
    hold_anchor(b)
    require("speech").say(lines[1], true)
    return true
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
        local head = { kind = "choice", choice = cp, n = ci, of = #cs }
        items[#items + 1] = head
        local hs = heroes_under(cp, "WBP_AwayMission_Choice_HeroSelection_C")
        for hi, h in ipairs(hs) do
            items[#items + 1] = { kind = "hero", choice = cp, hero = path_of(h), name = names[hi] or ("Hero " .. hi) }
        end
        -- A choice with no heroes shown said nothing about it, and a player
        -- could not tell why no one could be picked (Ocampa, choice 2,
        -- German game, outside report, 2026-10-17; cause not yet found).
        if #hs == 0 then head.no_heroes = true end
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
        if ro and ro:IsValid() then skill = require("text").skill_icon_name(ro:GetFName():ToString()) or skill end
    end)
    return skill, plain(text_of(c.AttributeAmount))
end

-- The active choice is the one whose button says "Confirm"; the others say
-- "Lock In". Each choice keeps a hero marked (SelectedStateWidget) even
-- when it is not the active one (read 2026-10-11).
-- A hero in the choice's team. SelectedStateWidget marks only the hero
-- clicked last; with two chosen, Kes and Tuvok went (Skill 35) while only
-- Tuvok was marked and Confirm named only him. A hero already in the team
-- shows LockedWidget (VM, 2026-10-14).
-- LockedWidget alone is the team: SelectedStateWidget stays on the hero
-- clicked last even when that click took the hero off again, and Joe Carey
-- was read "selected" while only Chakotay was (marks read after pick and
-- unpick: picked = Locked and Selected, unpicked = Selected only, the other
-- picked hero = Locked only; Dauntless, VM, 2026-10-18).
local function chosen(h)
    local yes = false
    pcall(function()
        local w = h.LockedWidget
        if w and w:IsValid() and screen.shown(w) then yes = true end
    end)
    return yes
end

-- A hero's value in the task's skill as the screen shows it ("25"), or nil
-- for none ("-", shown as a lock).
local function hero_value(h)
    local v = plain(text_of(h.WBP_HeroAbilityIcon and h.WBP_HeroAbilityIcon.AttributeValue))
    if v == "" or v == "-" then return nil end
    return v
end

-- A hero the game will not put on the task: NotSelectableWidget, a trait
-- the task requires. A hero with none of the skill ("-") can still be
-- selected: Tom Paris on a Science task gave 5% (VM, 2026-10-27).
local function blocked(h)
    local yes = false
    pcall(function()
        local w = h.NotSelectableWidget
        if w and w:IsValid() and screen.shown(w) then yes = true end
    end)
    return yes
end

-- A hero who adds to the task: has its skill and is not blocked. Only
-- these count for "one or more" and "add another hero" (the tutorial:
-- "more than one hero ... if they possess the required skill").
local function can_take(h)
    return hero_value(h) ~= nil and not blocked(h)
end

-- The success chance the game works out when heroes are picked: the window's
-- OnHeroesSelected(Chance, bCriticalSuccessCheck), a blueprint event
-- (header dump made on the System Map, 2026-10-18; firefly82's lead). The
-- game's tutorial says the chance is shown when the skill is below the
-- requirement, so only a chance under certain is said.
local last_chance = nil   -- { value = 0 to 100, at = os.clock() }
local chance_hooked = false
local CHANCE_HOOK = "/Game/STVoyager/Events/AwayMissions/UI/WBP_Dialogue_Window_AwayMission.WBP_Dialogue_Window_AwayMission_C:OnHeroesSelected"
-- The window's OnNoHeroesSelected says the chance is gone (the last hero
-- taken off a choice); it replaced a 30-second expiry that dropped the
-- chance while a hero still stood on the choice (firefly82's review,
-- 2026-10-19, tested by them in a German away mission).
local NO_HEROES_HOOK = "/Game/STVoyager/Events/AwayMissions/UI/WBP_Dialogue_Window_AwayMission.WBP_Dialogue_Window_AwayMission_C:OnNoHeroesSelected"
local cleared_by_game = false
local function ensure_chance_hook()
    if chance_hooked then return end
    if not StaticFindObject(CHANCE_HOOK) then return end   -- loads with the first away mission
    chance_hooked = pcall(RegisterHook, CHANCE_HOOK, function(_, chance, crit)
        pcall(function()
            local v = chance:get()
            if type(v) ~= "number" then return end
            -- Always a fraction (0.925 for 92.5%; firefly82, 2026-10-19).
            v = v * 100
            local c = false
            pcall(function() c = crit:get() == true end)
            last_chance = { value = math.floor(v + 0.5), at = os.clock(), crit = c }
            print("[VoyagerAccess] away: success chance " .. last_chance.value .. (c and " (critical check)" or "") .. "\n")
        end)
    end)
    if StaticFindObject(NO_HEROES_HOOK) then
        cleared_by_game = pcall(RegisterHook, NO_HEROES_HOOK, function()
            last_chance = nil
            print("[VoyagerAccess] away: no heroes selected, chance cleared\n")
        end)
    end
end
M.ensure_chance_hook = ensure_chance_hook

-- With bCriticalSuccessCheck the team meets the requirement: success is
-- certain and the number is the chance of a critical success, the golden
-- part of the game's chance bar. "success chance 5%" was said for a choice
-- that could not fail, and the result was a success (firefly82's review,
-- 2026-10-19). "requirement met, outstanding success chance 11%" sounded
-- as if 11% were the chance of success, and "outstanding" was the mod's
-- word for what the game's result calls "Critical Success" (Casey,
-- 2026-10-26). The skill and the requirement are said with the hero, as
-- the screen shows them next to the bar. Sentences without the last full
-- stop: the caller ends the line.
local function chance_words()
    ensure_chance_hook()
    if not last_chance then return nil end
    if not cleared_by_game and os.clock() - last_chance.at >= 30 then return nil end
    if last_chance.crit then
        if last_chance.value <= 0 then return "Will succeed" end
        -- The game sends more than 1 when the team is far over the
        -- requirement: "Team Command 69, 32 needed ... 116% chance" (Casey's
        -- own play, 0.3.92). A bar is never fuller than full, so the most the
        -- screen shows is 100%.
        return "Will succeed. " .. math.min(last_chance.value, 100) .. "% chance of a critical success"
    end
    if last_chance.value < 100 then
        return "Success chance " .. last_chance.value .. "%"
    end
    return nil
end

-- "Team Command 52, 36 needed. " when two or more heroes are on the choice:
-- the game adds their values (its tutorial: "the (cumulative) skill
-- value"), and the screen shows each hero's value and the requirement, not
-- the sum. Said only when the sum agrees with the game's own word on the
-- requirement (bCriticalSuccessCheck): a bonus the heroes' numbers leave
-- out would make the mod's sum disagree with the game (Casey, 2026-10-26:
-- no numbers that contradict each other).
local function team_words(it, c)
    if not (last_chance and mission_items) then return nil end
    local skill, needed = choice_skill(c)
    local n = tonumber(needed)
    if not n then return nil end
    local sum, count = 0, 0
    for _, o in ipairs(mission_items) do
        if o.kind == "hero" and o.choice == it.choice then
            local h = StaticFindObject(o.hero)
            if h and h:IsValid() and chosen(h) then
                local v = tonumber(plain(text_of(h.WBP_HeroAbilityIcon and h.WBP_HeroAbilityIcon.AttributeValue)))
                if v then sum, count = sum + v, count + 1 end
            end
        end
    end
    if count < 2 then return nil end
    if (sum >= n) ~= (last_chance.crit == true) then
        print("[VoyagerAccess] away: team sum " .. sum .. " of " .. n .. " disagrees with the game ("
            .. tostring(last_chance.crit) .. "), not said\n")
        return nil
    end
    return "Team " .. skill .. " " .. sum .. ", " .. needed .. " needed. "
end

-- Ready to confirm: the game enables the button once a hero is on the
-- choice. Matching its English word "Confirm" broke every away mission in
-- another language: no hero was ever "selected" and Confirm said to pick a
-- hero first (a forum player in the cornfield; reproduced in German, VM,
-- 2026-10-16).
local function is_active(c)
    local cb = c.ConfirmButton
    local ok, en = pcall(function() return cb:GetIsEnabled() end)
    if ok and en ~= nil then return en end
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
            -- By the label's name too: in German it reads "Erschöpft" (VM,
            -- 2026-10-16).
            if tp and tp:sub(1, #hp) == hp and screen.shown(t)
                and (tp:find("%.CommonTextBlock_184$") or plain(text_of(t)) == "Fatigued") then
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
-- Items have their own widgets beside each resource widget class, with the
-- item's name in text (same scan: 24 item rewards, none read before).
local ITEM_CLASSES = {
    WBP_ResourceReward_AwayMissionChoice_C = "WBP_ItemReward_AwayMissionChoice_C",
    WBP_ResourceReward_AwayMissionChallengeResult_C = "WBP_ItemReward_AwayMissionChallengeResult_C",
    WBP_AwayMission_Consequences_ResourceReward_C = "WBP_AwayMission_Consequences_ItemsReward_C",
}
local function item_rewards(choice_path, cls, out)
    for _, w in ipairs(FindAllOf(cls) or {}) do
        local wp = w:IsValid() and path_of(w)
        if wp and (choice_path == "" or wp:sub(1, #choice_path + 1) == choice_path .. ".") and screen.shown(w) then
            local name, amount = "", ""
            pcall(function() name = plain(text_of(w.ItemNameTextBlock)) end)
            if name == "" then pcall(function() name = plain(text_of(w.ResourceName)) end) end
            pcall(function() amount = plain(text_of(w.ItemAmountTextBlock)):gsub("^%+", "") end)
            if amount == "" then pcall(function() amount = plain(text_of(w.ResourceAmount)):gsub("^%+", "") end) end
            if name ~= "" then
                out[#out + 1] = (amount ~= "" and amount ~= "1") and (amount .. " " .. name) or name
            end
        end
    end
end

local function choice_rewards(choice_path, cls)
    local out = {}
    cls = cls or "WBP_ResourceReward_AwayMissionChoice_C"
    for _, w in ipairs(FindAllOf(cls) or {}) do
        local wp = w:IsValid() and path_of(w)
        if wp and (choice_path == "" or wp:sub(1, #choice_path + 1) == choice_path .. ".") and screen.shown(w) then
            local amount = ""
            pcall(function() amount = plain(text_of(w.ResourceAmountTextBlock)):gsub("^%+", "") end)
            -- The mission summary's reward names it ResourceAmount.
            if amount == "" then pcall(function() amount = plain(text_of(w.ResourceAmount)):gsub("^%+", "") end) end
            local res = "resources"
            pcall(function()
                local ro = w.ResourceImage.Brush.ResourceObject
                if ro and ro:IsValid() then res = require("text").icon_name(ro:GetFName():ToString()) or res end
            end)
            if amount ~= "" then out[#out + 1] = amount .. " " .. res end
        end
    end
    if ITEM_CLASSES[cls] then pcall(item_rewards, choice_path, ITEM_CLASSES[cls], out) end
    return table.concat(out, ", ")
end

-- A choice with lasting consequences has a golden outline, which a sighted
-- player sees before choosing; only the game's "consequences" toast after
-- Confirm said so (firefly82's review, 2026-10-24). The outline is the
-- choice text's ImportantOverlay (WBP_Dialogue_Choice_AwayMission_Text in
-- the widget dump; no other choice widget has one), and the native
-- STVDialogueChoice:SetContent takes the answer node's bIsImportant (header
-- dump of 2026-10-18). Not yet seen in play: an outline that is always
-- shown would mark every choice, and the log line says when it is found.
local function important(c)
    local o = nil
    pcall(function()
        local x = c.RightButton.ImportantOverlay
        if x and x:IsValid() then o = x end
    end)
    if not o then
        -- Not a named member: by its path inside the choice.
        local prefix = path_of(c) .. "."
        for _, x in ipairs(FindAllOf("Overlay") or {}) do
            local xp = x:IsValid() and path_of(x)
            if xp and xp:sub(1, #prefix) == prefix and xp:find("%.ImportantOverlay$") then o = x end
        end
    end
    if not (o and screen.shown(o)) then return false end
    local okp, op = pcall(function() return o:GetRenderOpacity() end)
    return not (okp and type(op) == "number" and op < 0.1)
end

local function item_label(it)
    -- Hooked while the mission is up, before a hero is picked.
    pcall(ensure_chance_hook)
    local c = StaticFindObject(it.choice)
    if not (c and c:IsValid()) then return nil end
    if it.kind == "choice" then
        -- Short lines, the skill and its number said once here and only the
        -- hero's number on each hero line, so Up and Down compare the heroes
        -- (Casey, 2026-10-26: "a screen reader has to listen to each line
        -- all at once"). Was "Choice 1 of 2: Look for footprints. Needs
        -- Command 29. Trait: Survivalist. Reward: 200 Deuterium."
        local parts = {}
        local wording = ""
        pcall(function() wording = plain(text_of(c.RightButton.ChoiceText)) end)
        if wording ~= "" then parts[#parts + 1] = wording end
        pcall(function()
            local rt = c.RightButton.RequirementText
            if rt and rt:IsValid() and screen.shown(rt) then
                local t = plain(text_of(rt)):gsub("^%[", ""):gsub("%]$", "")
                if t ~= "" then parts[#parts + 1] = t end
            end
        end)
        local skill, needed = choice_skill(c)
        if needed ~= "" and needed ~= "-" then parts[#parts + 1] = skill .. " " .. needed end
        local ok, reward = pcall(choice_rewards, it.choice)
        if ok and reward ~= "" then parts[#parts + 1] = require("tr").fill("Reward {s}", reward) end
        for i, s in ipairs(parts) do parts[i] = (s:gsub("[%.%s]+$", "")) end
        local label = #parts > 0 and ((table.concat(parts, ". ") .. "."):gsub("([!?])%.", "%1")) or "Task."
        if it.no_heroes then label = label:gsub("%.?%s*$", "") .. ". No heroes are listed for this choice." end
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
        -- In the dialogue choices' words (dialogue.lua).
        if important(c) then
            print("[VoyagerAccess] mission: golden outline on " .. it.choice:match("([^%.]+)$") .. "\n")
            label = label:gsub("%.?%s*$", "") .. ". Major decision."
        end
        -- Who is on it, with the game's chance; or where to pick. Heroes
        -- can be stacked, which the screen does not say: "one or more" when
        -- two or more heroes can take the task (the game's tutorial:
        -- "You can select more than one hero for a challenge").
        local who, able, open = {}, 0, 0
        for _, o in ipairs(mission_items or {}) do
            if o.kind == "hero" and o.choice == it.choice then
                local h = StaticFindObject(o.hero)
                if h and h:IsValid() then
                    if is_active(c) and chosen(h) then who[#who + 1] = o.name end
                    if can_take(h) then able = able + 1 end
                    if not blocked(h) then open = open + 1 end
                end
            end
        end
        -- Who is selected even when the game gave no chance, so the line
        -- never says to select while the hero lines say "selected"; and no
        -- "select" where nobody can be (Fable review, 2026-10-27).
        if #who > 0 then
            local names = #who == 1 and who[1] or (table.concat(who, ", ", 1, #who - 1) .. require("tr").word(" and ") .. who[#who])
            local cw = chance_words()
            label = label:gsub("%.?%s*$", "") .. ". " .. require("tr").fill("{s} selected", names) .. "." .. (cw and (" " .. cw .. ".") or "")
        elseif able >= 2 then
            label = label:gsub("%.?%s*$", "") .. ". Select one or more heroes below."
        elseif open > 0 and not it.no_heroes then
            label = label:gsub("%.?%s*$", "") .. ". Select a hero below."
        end
        return string.format("Task %d of %d: %s", it.n, it.of, label)
    elseif it.kind == "hero" then
        local h = StaticFindObject(it.hero)
        if not (h and h:IsValid()) then return nil end
        local skill = choice_skill(c)
        local value = hero_value(h)
        -- Only the hero's number: the task line says the skill and what it
        -- needs, so Up and Down compare the heroes (Casey, 2026-10-26).
        -- "enough" weighed one hero alone while the game adds the team's
        -- values; whether the team meets it is the game's own word, said
        -- with the chance.
        local text = it.name .. ", " .. (value or require("tr").fill("no {s}", skill))
        -- Tired heroes show "Fatigued" over their portrait and lower
        -- values; say it with the hero (2026-10-14).
        local okf, tired = pcall(fatigued, it.choice:match("^(.-WBP_Dialogue_Window_AwayMission_C_%d+)"))
        if okf then
            for _, n in ipairs(tired) do if n == it.name then text = text .. ", fatigued" end end
        end
        -- A choice that asks for a trait ("Trait: Pilot") helps the hero who
        -- has it; nothing on the hero said so (Investigating the Array,
        -- VM, 2026-10-15).
        local want = nil
        pcall(function() want = (require("dialogue").away_choice_label(c) or ""):match("Trait: ([^%.]+)") end)
        pcall(function()
            local has = trait_of(it.name)
            if want and has ~= "" and has:lower():find(want:lower(), 1, true) then
                text = text .. ", has the " .. want .. " trait"
            end
        end)
        -- The game marks a hero who cannot take this choice (a trait the
        -- choice requires: "Use Saboteur expertise" with no Saboteur on the
        -- team) with NotSelectableWidget; the line read like any other until
        -- Enter was refused (Operation Fort Knox, VM, 2026-10-18). A hero
        -- with none of the skill can still be selected, so says only that.
        if blocked(h) then
            text = it.name .. ", can't do it" .. (want and (", " .. require("tr").fill("needs {s}", want)) or "")
        end
        if is_active(c) and chosen(h, it.name) then
            text = text .. ", selected"
            local cw = chance_words()
            if cw then text = text .. ". " .. (team_words(it, c) or "") .. cw end
        end
        return text .. "."
    else
        -- Casey pressed Enter on the inactive choice's Lock In and nothing
        -- happened (2026-10-11). So say who it confirms, or that a hero must
        -- be picked for this choice first.
        if not is_active(c) then return "Lock In, no hero yet." end
        -- Several heroes can go together; only the last was named (2026-10-14:
        -- "Confirm with Tom Paris" sent Harry Kim too).
        local who = {}
        for _, o in ipairs(mission_items or {}) do
            if o.kind == "hero" and o.choice == it.choice then
                local h = StaticFindObject(o.hero)
                if h and h:IsValid() and chosen(h, o.name) then who[#who + 1] = o.name end
            end
        end
        if #who == 0 then return "Lock In, no hero yet." end
        local names = #who == 1 and who[1] or (table.concat(who, ", ", 1, #who - 1) .. require("tr").word(" and ") .. who[#who])
        local cw = chance_words()
        return "Confirm with " .. names .. (cw and (". " .. (team_words(it, c) or "") .. cw) or "") .. "."
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

-- Page Down and Page Up: the next or previous task line, past its heroes
-- and Lock In (Casey, 2026-10-26: one flat list, with a way to skip).
-- At the first or last task the same task is said again, as list ends are.
function M.mission_task(dir)
    refresh()
    if #mission_items == 0 then return end
    local i = mission_index or 1
    -- Page Up from a hero goes to its own task first.
    if dir < 0 and mission_items[i] and mission_items[i].kind ~= "choice" then
        while i > 1 and mission_items[i].kind ~= "choice" do i = i - 1 end
    else
        local j = i + dir
        while mission_items[j] and mission_items[j].kind ~= "choice" do j = j + dir end
        if mission_items[j] then i = j end
        while i > 1 and mission_items[i].kind ~= "choice" do i = i - 1 end
    end
    mission_index = i
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
            -- As the label says it: chosen() was true for a hero the game had
            -- refused (the choice is not active until a valid hero is on it).
            local was = false
            -- "selected" can be followed by the success chance.
            pcall(function() was = (item_label(it) or ""):find(", selected[%.,]") ~= nil end)
            press(h.Button)
            -- What changed, said short: the hero's whole line is said when
            -- the arrows reach it. The new chance only: "up from 83%" was
            -- dropped as words for what the player just heard (Casey,
            -- 2026-10-27). The pressed hero's own item, and nothing after
            -- another key: an Enter on a second task within 600 ms would
            -- have said this hero with that task's chance (GPT review,
            -- 2026-10-27).
            local key_at = require("keys").key_count
            ExecuteInGameThreadWithDelay(600, function()
                pcall(function()
                    if require("keys").key_count ~= key_at then return end
                    local label = item_label(it)
                    if not label then return end
                    local c = StaticFindObject(it.choice)
                    if label:find(", selected[%.,]") then
                        local team = c and c:IsValid() and team_words(it, c) or ""
                        local cw = chance_words()
                        label = require("tr").fill("{s} selected", it.name) .. "." .. (cw and (" " .. (team or "") .. cw .. ".") or "")
                        -- Heroes can be stacked, which nothing on screen says.
                        local more = false
                        for _, o in ipairs(mission_items) do
                            local oh = o.kind == "hero" and o.choice == it.choice and StaticFindObject(o.hero)
                            if oh and oh:IsValid() and not chosen(oh) and can_take(oh) then more = true end
                        end
                        if more then label = label .. require("hints").text("add_hero", " You can add another hero.") end
                    elseif was then
                        local cw = chance_words()
                        label = require("tr").fill("{s} unselected", it.name) .. ". " .. (cw and (cw .. ".") or "No hero on this task.")
                    else
                        -- The game refused the hero without a sound: a choice
                        -- that needs a trait takes only heroes who have it
                        -- (Kes on "Trait: Talaxian", Rise, VM, 2026-10-16).
                        local c = StaticFindObject(it.choice)
                        -- The game's own reason first, as the choice shows it
                        -- (Requirement and RequirementText, filled through
                        -- ShowHeroRequirement): the trait guess below was wrong
                        -- once, in German (outside review, 2026-10-17).
                        local why = nil
                        pcall(function()
                            local prefix = it.choice .. "."
                            for _, cls in ipairs({ "CommonRichTextBlock", "CommonTextBlock" }) do
                                for _, t in ipairs(FindAllOf(cls) or {}) do
                                    local tp = t:IsValid() and path_of(t)
                                    local nm = tp and tp:sub(1, #prefix) == prefix and tp:match("([^%.]+)$")
                                    if not why and (nm == "Requirement" or nm == "RequirementText") and screen.shown(t) then
                                        local s = plain(text_of(t))
                                        if s ~= "" and not s:find("^%[") and not s:find("^#") then why = s end
                                    end
                                end
                            end
                        end)
                        local want = c and c:IsValid() and (require("dialogue").away_choice_label(c) or ""):match("Trait: ([^%.]+)")
                        local has = trait_of(it.name)
                        -- Worded as the hero lines say it (Casey, 2026-10-26).
                        if why then
                            label = it.name .. ", can't do it, " .. (why:gsub("[%.%s]+$", "")) .. "."
                        elseif want and not (has ~= "" and has:lower():find(want:lower(), 1, true)) then
                            label = it.name .. ", can't do it, " .. require("tr").fill("needs {s}", want) .. "."
                        else
                            label = it.name .. " was not selected. " .. label
                        end
                    end
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
        if label:find("no hero yet%.$") then
            require("speech").say(label, true)
            return
        end
        print("[VoyagerAccess] mission: confirm " .. it.choice:match("([^%.]+)$") .. "\n")
        require("speech").say("Confirming", true)
        cb:HandleButtonPressed()
        local path = path_of(cb)
        ExecuteInGameThreadWithDelay(require("screen").hold_ms(cb), function()
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

-- The mission window is looked at when something can have changed in it,
-- not every 300 ms (the mod's loops held the game long enough to swallow
-- keys; firefly82, 2026-10-21): the player's input (keys.lua), the mission
-- window's own events (ShowDialogue, FinishShowChoices, OnTriggerNextNode,
-- FinishShowingDialogueRow, seen in the window census of 2026-10-21;
-- dialogue.lua passes them on), a challenge result's text being typed
-- (PlayLine, story.lua) and a reward widget being made (popups.on_widget).
-- One look per game tick however many ask. The combat setup's text
-- (combat_prep_poll) is looked at by combat.lua's own look.
local poll_queued = false
function M.request_poll()
    if poll_queued then return end
    poll_queued = true
    ExecuteInGameThread(function()
        poll_queued = false
        local ok, err = pcall(M.mission_poll)
        if not ok then print("[VoyagerAccess] mission error: " .. tostring(err) .. "\n") end
    end)
end

M.combat_prep_poll = function() pcall(combat_prep_poll) end

function M.install()
    require("keys").on_any(M.request_poll)
    local popups = require("popups")
    for _, cls in ipairs({ "WBP_ResourceReward_AwayMissionChallengeResult_C", "WBP_ItemReward_AwayMissionChallengeResult_C",
        "WBP_AwayMission_ChallengeResult_C" }) do
        popups.on_widget(cls, function() M.request_poll() end)
    end
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
                                res = require("text").icon_name(ro:GetFName():ToString()) or res
                            end
                        end)
                        if amount ~= "" then rewards[#rewards + 1] = amount .. " " .. res end
                    end
                end
                pcall(item_rewards, rp, "WBP_ItemReward_AwayMissionChallengeResult_C", rewards)
                if #rewards > 0 then parts[#parts + 1] = "Reward: " .. table.concat(rewards, ", ") end
                -- Fatigue: the window's HeroStatus_Choices plaques show
                -- "Fatigued" in the same hero order as HeroStatus.
                local tired = fatigued(rp:match("^(.-WBP_Dialogue_Window_AwayMission_C_%d+)"))
                -- "Neelix, Tuvok and Chakotay", not "Neelix and Tuvok and Chakotay".
                if #tired > 0 then
                    local names = #tired == 1 and tired[1]
                        or (table.concat(tired, ", ", 1, #tired - 1) .. require("tr").word(" and ") .. tired[#tired])
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
                -- They also come in one at a time: "Reward: 3 dilithium" was
                -- read while 600 morale and 30 science points were still
                -- arriving (Kazon Raider, VM, 2026-10-16). Watch for more,
                -- and once the list has stopped growing for a second, say it
                -- whole.
                do
                    local said_n = #rewards
                    local base = text:gsub("%s*Reward: [^%.]*%.", "")
                    local function count(s) return s == "" and 0 or select(2, s:gsub(", ", "")) + 1 end
                    local function look(tries, last_n)
                        local done, n = false, last_n
                        pcall(function()
                            local late = choice_rewards(rp, "WBP_ResourceReward_AwayMissionChallengeResult_C")
                            if late == "" then late = choice_rewards("", "WBP_ResourceReward_AwayMissionChallengeResult_C") end
                            n = count(late)
                            if n > said_n and n == last_n then
                                done = true
                                print("[VoyagerAccess] mission result reward: " .. late .. "\n")
                                require("speech").say("Reward: " .. late, false)
                                require("dialogue").remember(base .. " Reward: " .. late .. ".")
                            end
                        end)
                        if not done and tries > 1 then
                            ExecuteInGameThreadWithDelay(1000, function() look(tries - 1, n) end)
                        end
                    end
                    ExecuteInGameThreadWithDelay(1000, function() look(15, -1) end)
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
-- The experience rows and hero ranks fill in while the summary animates,
-- and were said twice: "Experience: Successful Challenges x3 +150." and
-- then the whole list again (Distant Origin and Friendship One, VM,
-- 2026-10-21). They are said once the game has finished showing the
-- summary (dialogue.lua's consequences events), or after 5 s.
local outcome_final, outcome_wait = {}, {}
function M.outcome_finished()
    for _, w in ipairs(FindAllOf("WBP_AwayMissionOutcome_C") or {}) do
        local p = w:IsValid() and path_of(w)
        if p then outcome_final[p] = true end
    end
end

function M.outcome_text(path)
    local final = outcome_final[path]
    if not final and not outcome_wait[path] then
        outcome_wait[path] = true
        ExecuteInGameThreadWithDelay(5000, function()
            if outcome_final[path] == "timeout" then return end
            outcome_final[path] = "timeout"
            pcall(function() require("popups").reread_class("WBP_AwayMissionOutcome_C") end)
        end)
    end
    local function order(w)
        local parent = w:GetParent()
        return (parent and parent:IsValid()) and parent:GetChildIndex(w) or 0
    end
    local function under(cls)
        local list = {}
        for _, w in ipairs(FindAllOf(cls) or {}) do
            local p = w:IsValid() and path_of(w)
            if p and screen.inside(w, path) and screen.shown(w) then list[#list + 1] = w end
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
    -- The game's "finished" event came with the first row too ("x1 +50"
    -- alone again, Caretaker, VM, 2026-10-21); the heroes' ranks come
    -- last, so they must be up as well, or 5 s must have passed.
    local heroes_up = #under("WBP_AwayMissionHeroOutcome_C") > 0
    if not (final == "timeout" or (final and heroes_up)) then return sentences(parts) end
    if #exp > 0 then parts[#parts + 1] = "Experience: " .. table.concat(exp, ", ") end
    -- Each row's own ExperienceCache names its hero and final level. The
    -- rows used to be sorted by object name, which is the reverse of the
    -- screen, and paired with a name list in yet another order, and their
    -- texts were read while the level-up animation was still counting
    -- ("Seven of Nine: rank 5" for Joe Carey's rank, PC, 2026-10-18).
    -- TargetExperience is the levels gained plus the fraction of the next
    -- rank (Seven 1 to 3 with 25 of 700: 2.0357), so the final "of" comes
    -- from it, not from the counting text.
    local heroes = under("WBP_AwayMissionHeroOutcome_C")
    table.sort(heroes, function(a, b) return order(a) < order(b) end)
    local names = hero_names()
    for i, h in ipairs(heroes) do
        local name, rank, have, need = nil, nil, nil, nil
        pcall(function()
            local c = h.ExperienceCache
            name = require("events").hero_name(c.HeroName:ToString())
            rank = tostring(c.NewLevel)
            have = c.NewExperience
            local frac = h.TargetExperience - math.floor(h.TargetExperience)
            if have and have > 0 and frac > 0.0001 then need = math.floor(have / frac + 0.5) end
        end)
        if not rank then
            rank = plain(text_of(h.NewLevelText))
            local xp = plain(text_of(h.levelDisplay))
            have, need = xp:match("^(%d+)/(%d+)$")
        end
        local line = (name or names[i] or ("Hero " .. i)) .. ": rank " .. rank
        if have and need then line = line .. ", " .. have .. " of " .. need .. " experience to the next rank" end
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
    -- Choices and challenge results are parts of the away mission's
    -- dialogue window, which dialogue.lua knows from its events: outside it
    -- there is nothing to look for. Two searches over every object ran after
    -- every key all game long (2026-10-25).
    local okw, w = pcall(function() return require("dialogue").active() end)
    local away = okw and w and w:GetClass():GetFName():ToString():find("AwayMission", 1, true) ~= nil
    if not away then
        mission_sig = nil
        return
    end
    result_poll()
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
                require("speech").say("Left and Right, or Page Up and Page Down, jump between tasks.", false)
            end
        end
    end
end

return M
