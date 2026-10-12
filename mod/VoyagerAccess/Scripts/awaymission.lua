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
    if name == "" then return nil end
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
    return sentences(parts)
end

-- A slot's button: ...WBP_AwayMissionLoadout_C_N...<picker>.WidgetTree_N.OpenSelectionButton
-- The combat hero setup (WBP_CombatHeroLoadout, native
-- STVCombatHeroLoadoutWidget) has the same HeroPickers of STVHeroPicker
-- with a HeroPlaque, read from its class 2026-10-11 before any battle was
-- reached; its slots use the same labels, not yet heard in a battle.
local LOADOUTS = { WBP_AwayMissionLoadout_C = "Away team slot", WBP_CombatHeroLoadout_C = "Combat slot" }

local function loadout_of(path)
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
        and (path:find("WBP_AwayMissionLoadout_C_%d+") ~= nil or path:find("WBP_CombatHeroLoadout_C_%d+") ~= nil)
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
    if hero then return head .. ": " .. hero end
    return head .. ", empty. Enter to choose a hero."
end

-- A hero in the list a slot opens.
-- WBP_SelectionButtonCombat is the combat list's button (native
-- STVCombatHeroSelectionButton); assumed to have a HeroPlaque like the away
-- team's, not yet seen.
function M.is_hero_button(path)
    return path ~= nil and (path:find("WBP_AwayMissionHeroSelectionButton_C_%d+$") ~= nil
        or path:find("WBP_SelectionButtonCombat_C_%d+$") ~= nil)
end

function M.hero_label(path)
    local b = StaticFindObject(path)
    if not (b and b:IsValid()) then return nil end
    local ok, plaque = pcall(function() return b.HeroPlaque end)
    return ok and plaque_text(plaque) or nil
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
local function is_active(c)
    local cb = c.ConfirmButton
    return plain(text_of(cb and cb.Name_TextBlock)):lower() == "confirm"
end

local function item_label(it)
    local c = StaticFindObject(it.choice)
    if not (c and c:IsValid()) then return nil end
    if it.kind == "choice" then
        local label = require("dialogue").away_choice_label(c) or "Choice"
        return string.format("Choice %d of %d: %s", it.n, it.of, label)
    elseif it.kind == "hero" then
        local h = StaticFindObject(it.hero)
        if not (h and h:IsValid()) then return nil end
        local skill, needed = choice_skill(c)
        local value = plain(text_of(h.WBP_HeroAbilityIcon and h.WBP_HeroAbilityIcon.AttributeValue))
        local text = it.name .. ", " .. ((value == "" or value == "-") and ("no " .. skill)
            or (skill .. " " .. value .. (needed ~= "" and (" of " .. needed .. " needed") or "")))
        local sel = h.SelectedStateWidget
        if is_active(c) and sel and sel:IsValid() and screen.shown(sel) then text = text .. ", selected" end
        return text .. "."
    else
        -- Casey pressed Enter on the inactive choice's Lock In and nothing
        -- happened (2026-10-11). So say who it confirms, or that a hero must
        -- be picked for this choice first.
        if not is_active(c) then return "Lock In: select a hero for this choice first." end
        local who = nil
        for _, o in ipairs(mission_items or {}) do
            if o.kind == "hero" and o.choice == it.choice then
                local h = StaticFindObject(o.hero)
                local sel = h and h:IsValid() and h.SelectedStateWidget
                if sel and sel:IsValid() and screen.shown(sel) then who = o.name end
            end
        end
        if not who then return "Lock In: select a hero for this choice first." end
        return "Confirm with " .. who .. "."
    end
end

local function say_item()
    local it = mission_items[mission_index]
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
            print("[VoyagerAccess] mission: select " .. it.name .. "\n")
            press(h.Button)
            ExecuteInGameThreadWithDelay(300, function() pcall(say_item) end)
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
                if have:match("^%d+$") and need:match("^%d+$") then parts[#parts + 1] = have .. " of " .. need end
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
                local names = hero_names()
                local tired = {}
                local window = rp:match("^(.-WBP_Dialogue_Window_AwayMission_C_%d+)")
                if window then
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
                end
                if #tired > 0 then parts[#parts + 1] = table.concat(tired, " and ") .. (#tired == 1 and " is" or " are") .. " fatigued" end
                local text = sentences(parts)
                print("[VoyagerAccess] mission result: " .. text .. "\n")
                require("speech").say_long(text)
                require("dialogue").remember(text)
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

-- When a new set of choices comes up, read the first one.
function M.mission_poll()
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
        end
    end
end

return M
