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
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.%s*$", "") end
    return table.concat(parts, ". ") .. "."
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
function M.is_slot(path)
    return path ~= nil and path:find("WBP_AwayMissionLoadout_C_%d+") ~= nil
        and path:find("%.OpenSelectionButton$") ~= nil
end

function M.slot_label(path)
    local L = loadout()
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
    local head = string.format("Away team slot %d of %d", index, count)
    if hero then return head .. ": " .. hero end
    return head .. ", empty. Enter to choose a hero."
end

-- A hero in the list a slot opens.
function M.is_hero_button(path)
    return path ~= nil and path:find("WBP_AwayMissionHeroSelectionButton_C_%d+$") ~= nil
end

function M.hero_label(path)
    local b = StaticFindObject(path)
    if not (b and b:IsValid()) then return nil end
    return plaque_text(b.HeroPlaque)
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

return M
