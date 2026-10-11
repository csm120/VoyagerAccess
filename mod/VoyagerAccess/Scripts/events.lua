-- Point-of-interest events: the window with a title, a description and a
-- list of options (WBP_POIMultipleChoice, options WBP_POISelectableOption).
--
-- An option's button shows its wording (a rich text the button reader did
-- not see), a reward amount next to a resource ICON, and a chance bar drawn
-- in colors. Read 2026-10-10:
--   * the reward's icon is a material named after the resource
--     ("MI_UI_Deuterium_WhiteNoBG");
--   * each option is an STVPOIEventOption whose GetOptionResults maps an
--     outcome (ESTVResultType: 0 Excellent, 1 Good, 2 Average, 3 Bad,
--     4 Terrible) to a result with a Weight; "Destroy the vessel" had Good
--     70 and Bad 30. Chances are the weights over their total. Each result
--     also has BonusWeight entries, not yet read, so the bar the game draws
--     may differ when bonuses apply.
--   * a requirement the ship does not meet is marked <ColorNegative> in the
--     wording ("[Torpedo Launch Bay <ColorNegative>Lvl 1</>]").

local M = {}

-- The option's own risk label (ESTVRiskType).
local RISKS = { [0] = "No risk", [1] = "Low risk", [2] = "Medium risk", [3] = "High risk", [4] = "Extreme risk" }

local OUTCOMES = { [0] = "excellent", [1] = "good", [2] = "average", [3] = "bad", [4] = "terrible" }

local function plain(s)
    s = s:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", "\""):gsub("&#39;", "'")
    return (s:gsub("<[^>]*>", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function text_of(w)
    if not (w and w:IsValid()) then return "" end
    local ok, s = pcall(function() return w:GetText():ToString() end)
    return ok and s or ""
end

-- Wording without its bracketed requirement: the option's own text has an
-- empty "[]" where the button shows "[Torpedo Launch Bay Lvl 1]".
local function bare(s)
    return plain((s:gsub("%[[^%[%]]*%]", "")))
end

-- The STVPOIEventOption whose wording matches the button's.
local function option_for(wording)
    local want = bare(wording)
    for _, o in ipairs(FindAllOf("STVPOIEventOption") or {}) do
        if o:IsValid() and not o:GetFullName():find("Default__", 1, true) then
            local ok, d = pcall(function() return o:GetOptionDescription():ToString() end)
            if ok and bare(d) == want then return o end
        end
    end
    return nil
end

-- "Good: 70% chance of a good outcome, 30% chance of a bad
-- outcome", or nil.
local function chances(o)
    local list, total = {}, 0
    local ok = pcall(function()
        for k, v in pairs(o:GetOptionResults()) do
            local outcome = k:get()
            local weight = v:get().Weight
            if weight and weight > 0 then
                list[#list + 1] = { outcome = outcome, weight = weight }
                total = total + weight
            end
        end
    end)
    if not ok or total == 0 then return nil end
    table.sort(list, function(a, b) return a.outcome < b.outcome end)
    -- "70% chance of a good outcome, 30% chance of a bad outcome" (Casey,
    -- 2026-10-11: players misread "good 70%, average 30%" as statistics).
    -- An option with one outcome says nothing: its bar is one solid block,
    -- and "always good" confused more than it told (Casey, 2026-10-11).
    -- Sighted players see only the maximum reward and the colored bar, so
    -- no per-outcome amounts are read (Casey chose parity, 2026-10-11).
    if #list == 1 then return nil end
    local out = {}
    -- The glance a sighted player gets from the bar ("mostly green"),
    -- said before the numbers in the game's own words (Casey, 2026-10-11).
    -- Excellent and good count as good, bad and terrible as bad, and
    -- average as half of each.
    local score = 0
    for _, e in ipairs(list) do
        local share = e.weight / total
        if e.outcome <= 1 then score = score + share
        elseif e.outcome == 2 then score = score + share / 2 end
    end
    score = math.floor(score * 100 + 0.5)
    -- One word; the percentages after it give the detail ("likely" was
    -- redundant with them, Casey 2026-10-11).
    local verdict = score >= 65 and "Good" or score > 35 and "Mixed" or "Bad"
    for _, e in ipairs(list) do
        local word = OUTCOMES[e.outcome] or "another"
        local article = word == "another" and "" or (word:match("^[aeiou]") and "an " or "a ")
        out[#out + 1] = string.format("%d%% chance of %s%s outcome",
            math.floor(e.weight * 100 / total + 0.5), article, word)
    end
    return verdict .. ": " .. table.concat(out, ", ")
end

-- Rooms that improve an option. Each result's BonusWeight entries
-- (FSTVBonusInRandomOutcome: RoomType, BonusPercent, or a tech or shuttle
-- requirement) raise that outcome when the ship has the room. How the game
-- applies BonusPercent is not known yet (2026-10-11), so the chances stay
-- the base values and the option says what would improve it.
local ROOM_ENUM = nil
local function room_names(o)
    ROOM_ENUM = ROOM_ENUM or StaticFindObject("/Script/STVoyager.ESTVRoomType")
    local names, seen = {}, {}
    pcall(function()
        for k, v in pairs(o:GetOptionResults()) do
            local outcome = k:get()
            if outcome <= 1 then   -- bonuses toward excellent or good
                v:get().BonusWeight:ForEach(function(_, e)
                    local t = e:get().RoomType
                    if t and t > 0 and not seen[t] then
                        seen[t] = true
                        local raw = ROOM_ENUM:GetNameByValue(t):ToString():gsub("^ESTVRoomType::", "")
                        names[#names + 1] = (raw:gsub("(%l)(%u)", "%1 %2"))
                    end
                end)
            end
        end
    end)
    return names
end

-- "Up to 396 Deuterium" for each reward shown on the button.
local function rewards(b)
    local out = {}
    pcall(function()
        b.MaxRewards:ForEach(function(_, e)
            local r = e:get()
            local amount = plain(text_of(r.RewardAmount_Text)):gsub("^%+", "")
            local ok, icon = pcall(function() return r.Reward_Image.Brush.ResourceObject:GetFName():ToString() end)
            local res = ok and icon:match("^MI_UI_(%a+)") or "resources"
            if amount ~= "" then out[#out + 1] = "up to " .. amount .. " " .. res end
        end)
    end)
    return table.concat(out, ", ")
end

-- "[Torpedo Launch Bay <ColorNegative>Lvl 1</>]" is a requirement not met;
-- returns it as text, or nil.
local function unmet(b)
    local needs = text_of(b.ChoiceButton_Text):match("%[([^%[%]]-<ColorNegative>.-)%]")
    return needs and (plain(needs):gsub("Lvl", "level")) or nil
end

-- "1 of 2" among the options that can be picked. Locked options take no
-- focus, so counting them made Casey hear "1 of 3", then "3 of 3"
-- (2026-10-11); they are read when the event opens instead.
local function position(b)
    local list = b:GetParent()
    if not (list and list:IsValid()) then return nil end
    local screen = require("screen")
    local mine = b:GetFullName()
    local n, index, locked = 0, nil, 0
    for i = 0, list:GetChildrenCount() - 1 do
        local row = list:GetChildAt(i)
        if row and row:IsValid() and row:GetClass():GetFName():ToString() == "WBP_POISelectableOption_C"
            and screen.shown(row) then
            if unmet(row) then
                locked = locked + 1
            else
                n = n + 1
                if row:GetFullName() == mine then index = n end
            end
        end
    end
    if not index then return nil end
    -- "1 of 2, 1 locked": sighted players see locked options the whole time
    -- the window is open; R reads them (Casey, 2026-10-11).
    return index .. " of " .. n .. (locked > 0 and (", " .. locked .. " locked") or "")
end

-- The spoken label for an option button. A locked option starts "Locked:".
function M.option_label(b)
    local wording = text_of(b.ChoiceButton_Text)
    local needs = unmet(b)
    local text = plain(wording:gsub("%s*%[[^%[%]]*%]%s*", " "))
    local parts = { needs and ("Locked: " .. text) or text }
    if needs then parts[#parts + 1] = "Needs " .. needs end
    local r = rewards(b)
    if r ~= "" then parts[#parts + 1] = r:sub(1, 1):upper() .. r:sub(2) end
    local o = option_for(wording)
    if o then
        local ok, risk = pcall(function() return o.Risk end)
        local ok2, leaving = pcall(function() return o.bLeaving end)
        if ok and RISKS[risk] and not (ok2 and leaving) then parts[#parts + 1] = RISKS[risk] end
    end
    local c = o and chances(o)
    if c then parts[#parts + 1] = c:sub(1, 1):upper() .. c:sub(2) end
    local better = o and room_names(o) or {}
    if #better > 0 then parts[#parts + 1] = "Better with " .. table.concat(better, " or ") end
    -- Position among the event's options, so one option is not heard as
    -- running into the next ("Leave the storage alone..." is not "Leave for
    -- now"; Casey, 2026-10-11).
    local pos = position(b)
    if pos then parts[#parts + 1] = pos end
    for i, s in ipairs(parts) do parts[i] = s:gsub("%.$", "") end
    return table.concat(parts, ". ") .. "."
end

-- The locked options on screen, read when the event window opens.
function M.locked_summary()
    local screen = require("screen")
    local out = {}
    for _, w in ipairs(FindAllOf("WBP_POISelectableOption_C") or {}) do
        local p = w:IsValid() and w:GetFullName():match("^%S+%s+(.+)$")
        if p and p:find("^/Engine/Transient%.") and screen.shown(w) and unmet(w) then
            out[#out + 1] = M.option_label(w)
        end
    end
    return table.concat(out, " ")
end

return M
