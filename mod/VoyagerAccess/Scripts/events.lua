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
local speech = require("speech")
local crumb = require("crumb")

local function path_of(o)
    return o:GetFullName():match("^%S+%s+(.+)$")
end

-- The option's own risk label (ESTVRiskType).
local RISKS = { [0] = "No risk", [1] = "Low risk", [2] = "Medium risk", [3] = "High risk", [4] = "Extreme risk" }

local OUTCOMES = { [0] = "excellent", [1] = "good", [2] = "average", [3] = "bad", [4] = "terrible" }

local function plain(s)
    s = require("text").prep(s)  -- icons beside numbers, list line breaks (text.lua)
    s = s:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", "\""):gsub("&#39;", "'")
    return (s:gsub("<[^>]*>", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function text_of(w)
    if not (w and w:IsValid()) then return "" end
    local ok, s = pcall(function() return w:GetText():ToString() end)
    return ok and s or ""
end

-- The button's own STVPOIEventOption (WBP_POISelectableOption.CurrentOption).
-- Matching wording across every STVPOIEventOption asked options being torn
-- down for their description: the game crashed or the mod stopped on a Q
-- Trial's Repair Station, three times in four (VM, 2026-10-14).
-- Wording without its bracketed requirement: the option's own text has an
-- empty "[]" where the button shows "[Torpedo Launch Bay Lvl 1]".
local function bare(s)
    return plain((s:gsub("%[[^%[%]]*%]", "")))
end

local has_current = nil   -- does the option button's class have CurrentOption
local function option_for(b, wording)
    if has_current == nil then
        -- CurrentOption is declared by the native parent
        -- (STVPOIEventSelectableOptionButton), not the Blueprint class, so
        -- the parents are searched too. Looking at the Blueprint class alone
        -- always sent the full game to the demo's wording scan below, whose
        -- GetOptionDescription crashed the game at a Q Trial's Trading
        -- Station (3 of 3, VM, 2026-10-15).
        has_current = false
        pcall(function()
            local c, depth = b:GetClass(), 0
            while c and c:IsValid() and depth < 4 and not has_current do
                c:ForEachProperty(function(p)
                    if p:GetFName():ToString() == "CurrentOption" then has_current = true end
                end)
                c, depth = c:GetSuperStruct(), depth + 1
            end
        end)
    end
    if has_current then
        local ok, o = pcall(function() return b.CurrentOption end)
        if ok and o and o:IsValid() then return o end
        return nil
    end
    -- The demo's button has no CurrentOption (checked 2026-10-14), so there
    -- the option is still matched by wording, as through the whole demo.
    -- The full game always has the field and never scans.
    local want = bare(wording)
    for _, x in ipairs(FindAllOf("STVPOIEventOption") or {}) do
        if x:IsValid() and not x:GetFullName():find("Default__", 1, true) then
            local okd, d = pcall(function() return x:GetOptionDescription():ToString() end)
            if okd and bare(d) == want then return x end
        end
    end
    return nil
end

-- The chances the game really uses. Rooms add weight to outcomes (a Main
-- Deflector made Good 40 into 44; a Torpedo Launch Bay could add a Good
-- that had no base weight at all), and the BonusWeight entries' own fields
-- were all zero, so the base weights said "60% excellent, 40% bad" and the
-- result was "good" (Kazon wreck, VM, 2026-10-15). The game hands the
-- adjusted weights to the window's OnPreSelectButton(Map, TotalWeight) only
-- when the mouse hovers an option (keyboard focus does not), so the mod
-- hooks that function and, when an event opens, sweeps the mouse down the
-- option list once; whichever option IsHovered gets the weights.
local captured = {}   -- key_of(button) -> { {outcome, weight}, ... }
local hooked = false
-- The button and its wording: a button object reused for another option
-- must not keep the old numbers.
local function key_of(b)
    return path_of(b) .. "|" .. text_of(b.ChoiceButton_Text)
end
local HOOK = "/Game/STVoyager/Events/UI/WBP_POIMultipleChoice.WBP_POIMultipleChoice_C:OnPreSelectButton"
local function ensure_hook()
    if hooked then return end
    if not StaticFindObject(HOOK) then return end   -- the widget class loads with the first event
    local ok = pcall(RegisterHook, HOOK, function(_, map)
        pcall(function()
            local list = {}
            map:get().Map:ForEach(function(k, v)
                list[#list + 1] = { outcome = k:get(), weight = v:get() }
            end)
            for _, b in ipairs(FindAllOf("WBP_POISelectableOption_C") or {}) do
                if b:IsValid() and b:IsHovered() then captured[key_of(b)] = list end
            end
        end)
    end)
    hooked = ok
end

-- Options shown and not locked that have no captured weights yet.
local function uncaptured()
    local n = 0
    for _, b in ipairs(FindAllOf("WBP_POISelectableOption_C") or {}) do
        if b:IsValid() and path_of(b):find("^/Engine/Transient%.") and require("screen").shown(b)
            and not captured[key_of(b)] then
            local ok, en = pcall(function() return b:GetIsEnabled() end)
            if not (ok and en == false) then n = n + 1 end
        end
    end
    return n
end

-- Sweeps the mouse down the right-hand panel where the options are, then
-- calls done(). Does nothing but call done() when every option has its
-- weights already.
local sweeping = false
function M.sweeping_now() return sweeping end
function M.sweep(done)
    -- Fresh for each reading: a station met again after a room was built
    -- would keep the old odds under the same button and wording.
    if not sweeping then captured = {} end
    local ok = pcall(ensure_hook)
    if not (ok and hooked) or uncaptured() == 0 or sweeping then
        if done then done() end
        return
    end
    -- Any failure ends the sweep and still says the option: a sweep left
    -- marked as running would skip every later one (review, 2026-10-15).
    local finished = false
    -- The option that had focus when the sweep began. The game moves focus
    -- to the option under the mouse, so the sweep left it on the last one:
    -- the player heard "Safely search ..., 1 of 2" and Enter picked "Leave
    -- for now" (Abandoned Mining Station, VM, 2026-10-16). The mouse goes
    -- back over the first one it was seen on, and focus back to it.
    local orig_key, orig_y = nil, nil
    pcall(function()
        local cur = require("focus").current_path()
        for _, b in ipairs(FindAllOf("WBP_POISelectableOption_C") or {}) do
            local p = b:IsValid() and path_of(b)
            if p and cur and (cur == p or cur:sub(1, #p + 1) == p .. ".") then orig_key = key_of(b) end
        end
    end)
    local okv0, rr, ww, hh = false, nil, nil, nil
    local function finish()
        if finished then return end
        finished = true
        print("[VoyagerAccess] events: chances read from the game, " .. uncaptured() .. " option(s) without\n")
        local function after()
            sweeping = false
            pcall(function()
                for _, b in ipairs(FindAllOf("WBP_POISelectableOption_C") or {}) do
                    if b:IsValid() and orig_key and key_of(b) == orig_key then b:SetFocus() end
                end
            end)
            if done then pcall(done) end
        end
        if orig_y and okv0 then
            pcall(speech.ring_mouse, (0.83 * ww - ww / 2) / rr, (orig_y - hh / 2) / rr)
            ExecuteInGameThreadWithDelay(300, function() pcall(after) end)
        else
            after()
        end
    end
    local okv, w, h = pcall(function()
        local pc = FindFirstOf("PlayerController")
        local size = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportSize(pc)
        return size.X, size.Y
    end)
    if not (okv and w and h and h > 0) then return finish() end
    sweeping = true
    local r = 350 / 1080 * h   -- the helper's ring radius
    okv0, rr, ww, hh = true, r, w, h
    local x = 0.83 * w
    local ys = {}
    for y = 0.40 * h, 0.96 * h, 0.025 * h do ys[#ys + 1] = y end
    local i = 0
    local function step()
        if orig_key and not orig_y and i > 0 and captured[orig_key] then orig_y = ys[i] end
        i = i + 1
        if i > #ys or uncaptured() == 0 then return finish() end
        speech.ring_mouse((x - w / 2) / r, (ys[i] - h / 2) / r)
        ExecuteInGameThreadWithDelay(80, function()
            if not pcall(step) then finish() end
        end)
    end
    if not pcall(step) then finish() end
end

-- "Good: 70% chance of a good outcome, 30% chance of a bad
-- outcome", or nil. b is the option's button, for the game's own weights.
local function chances(o, b)
    local list, total = {}, 0
    local got = b and captured[key_of(b)]
    local ok = pcall(function()
        if got then
            for _, e in ipairs(got) do
                if e.weight and e.weight > 0 then
                    list[#list + 1] = { outcome = e.outcome, weight = e.weight }
                    total = total + e.weight
                end
            end
            return
        end
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
                        -- The game's own room name (ship.lua, RoomTypeToText),
                        -- as everywhere else: the enum gave "Engineering
                        -- Offices", English in any language (VM, French,
                        -- 2026-10-17).
                        local okn, name = pcall(function() return require("ship").type_name(t) end)
                        if not (okn and name and name ~= "") then
                            name = (ROOM_ENUM:GetNameByValue(t):ToString():gsub("^ESTVRoomType::", ""):gsub("(%l)(%u)", "%1 %2"))
                        end
                        names[#names + 1] = name
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
            -- Checked at each step: an unchecked brush read crashed the game
            -- (access violation, pcall cannot catch it) on the Repair
            -- Station's options in a Q Trial (VM, 2026-10-14).
            local icon = nil
            pcall(function()
                local img = r.Reward_Image
                if not (img and img:IsValid()) then return end
                local ro = img.Brush.ResourceObject
                if ro and ro:IsValid() then icon = ro:GetFName():ToString() end
            end)
            -- "SciencePoints" read as one word; text.icon_name says "science
            -- points", "experience", "crew" (reward scan, 2026-10-16).
            local res = icon and require("text").icon_name(icon) or "resources"
            -- "#999" is the widget's design-time text, left on an option with
            -- no reward: "Leave for now. Up to #999 deuterium" (Relay
            -- Station, VM, 2026-10-17).
            if amount:find("%d") and not amount:find("#", 1, true) then out[#out + 1] = "up to " .. amount .. " " .. res end
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

-- Heroes for an option (Q Trials points of interest, and wherever else an
-- option has WBP_POIAssignableHero buttons). A sighted player hovers an
-- option to open its row of portraits and clicks one, which carries the
-- option out with that hero (VM, 2026-10-14: a click sent B'Elanna). The
-- first button is "no hero". Left and Right choose one here; Enter on the
-- option then clicks the chosen hero's button.
local HERO_NAMES = { Char_Tom_Paris = "Tom Paris", Char_Neelix = "Neelix", Char_Carey = "Joe Carey",
    Char_Marla_Gilmore = "Marla Gilmore", Char_Torres = "B'Elanna", Char_Janeway = "Kathryn Janeway",
    Char_Kim = "Harry Kim", Char_Harry_Kim = "Harry Kim", Char_Doctor = "The Doctor", Char_The_Doctor = "The Doctor",
    Char_Tuvok = "Tuvok", Char_Chakotay = "Chakotay", Char_Kes = "Kes" }
local ATTR = nil
local chosen = {}   -- option path -> index into its heroes (1 is no hero)

-- The game's own name for a hero id. HERO_NAMES has the campaign's starting
-- crew only, and the game has dozens more (Seven, Kashyk, Ransom, Burke;
-- data scan, 2026-10-16), which were read as their raw ids.
local function hero_name(id)
    local name = nil
    pcall(function()
        local hm = FindFirstOf("STVHeroManager")
        local out = {}
        if hm and hm:IsValid() and hm:TryGetHeroDisplayNameFromId(FName(id), out) then
            name = out.OutHeroName:ToString()
        end
    end)
    if name and name ~= "" then return name end
    return HERO_NAMES[id] or (id:gsub("^Char_", ""):gsub("_", " "))
end
M.hero_name = hero_name

local function attribute_of(o)
    ATTR = ATTR or StaticFindObject("/Script/STVoyager.ESTVHeroAttribute")
    local name = nil
    pcall(function() name = ATTR:GetNameByValue(o.AssociatedAttribute):ToString():gsub("^ESTVHeroAttribute::", "") end)
    return name
end

local function heroes_of(b)
    local out = {}
    pcall(function()
        local used = b.NumUsedButtons or 0
        b.HeroButtons:ForEach(function(i, e)
            if #out >= used then return end
            local h = e:get()
            if not (h and h:IsValid()) then return end
            local none = h.isNoHero == true
            local id = ""
            pcall(function() id = h.CurrentHeroId:ToString() end)
            out[#out + 1] = { button = h, none = none,
                name = none and "No hero" or hero_name(id),
                value = text_of(h.AbilityValue_TXT):gsub("^0+(%d)", "%1"),
                tired = h.isFatigued == true, usable = h.bHeroSelectable ~= false }
        end)
    end)
    return out
end

local function hero_text(h, skill)
    if h.none then return "No hero" end
    local s = h.name .. ", " .. (skill or "skill") .. " " .. h.value
    if h.tired then s = s .. ", fatigued" end
    if not h.usable then s = s .. ", not available" end
    return s
end

-- Left and Right on an option with heroes. True when it handled the key.
function M.hero_step(path, dir)
    local b = path and StaticFindObject(path)
    if not (b and b:IsValid() and b:GetClass():GetFName():ToString() == "WBP_POISelectableOption_C") then return false end
    local list = heroes_of(b)
    if #list < 2 then return false end
    local i = (chosen[path] or 1) + dir
    if i < 1 then i = 1 elseif i > #list then i = #list end
    chosen[path] = i
    local o = option_for(b, text_of(b.ChoiceButton_Text))
    speech.say(hero_text(list[i], o and attribute_of(o)) .. ", " .. i .. " of " .. #list, true)
    return true
end

-- Enter on an option with a hero chosen: click that hero, which carries
-- the option out with them. True when it handled the key.
function M.enter(b, path)
    local i = chosen[path]
    if not (i and i > 1) then return false end
    local h = heroes_of(b)[i]
    if not (h and h.button:IsValid()) then return false end
    if not h.usable then
        speech.say(h.name .. " is not available for this", true)
        return true
    end
    chosen[path] = nil
    print("[VoyagerAccess] events: sending " .. h.name .. "\n")
    h.button:HandleButtonPressed()
    h.button:HandleButtonReleased()
    h.button:HandleButtonClicked()
    return true
end

-- An option that cannot be picked: a requirement not met, or disabled (a
-- trade the ship cannot afford takes no focus and was never read, while the
-- count said "1 of 4" and Down went to 4; Trading Station, VM, 2026-10-14).
local function is_locked(row)
    if unmet(row) then return true end
    local ok, en = pcall(function() return row:GetIsEnabled() end)
    return ok and en == false
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
            if is_locked(row) then
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
    local crumb = require("crumb")
    crumb.at("events: wording")
    local wording = text_of(b.ChoiceButton_Text)
    crumb.at("events: unmet")
    local needs = unmet(b)
    local text = plain(wording:gsub("%s*%[[^%[%]]*%]%s*", " "))
    -- "...for resource exposure: [Torpedo Launch Bay Lvl 1]" left a colon
    -- before the full stop: "exposure:." (Icy Planetoid, VM, 2026-10-15).
    text = (text:gsub("%s*:%s*$", ""))
    -- A trade: "Trade Food 150 for DEUTERIUM +150 deuterium" (Trading
    -- Station, Q Trials, VM, 2026-10-15) reads "Trade Food 150 for 150
    -- deuterium".
    text = (text:gsub(" for %u[%u%s%-]* %+([%d,]+) (%a[%a%s%-]*)$", " for %1 %2"))
    local parts = { is_locked(b) and ("Locked: " .. text) or text }
    if needs then parts[#parts + 1] = "Needs " .. needs end
    -- Bracketed notes other than room levels were dropped with the
    -- brackets: "[Shuttles: 2]", "[Science - Hero will be permanently
    -- lost]", "[3 CYCLES]", "[Original exits remain]" (scan of the game's
    -- text, 2026-10-15). Unmet ones are already said as "Needs".
    for inner in wording:gmatch("%[([^%[%]]*)%]") do
        if not inner:find("ColorNegative", 1, true) then
            local note = plain(inner)
            if note ~= "" and not note:find("Lvl%s*%d") then parts[#parts + 1] = note end
        end
    end
    -- A cost the ship cannot pay is shown in the negative color ("Pay
    -- <ColorNegative>Tritanium 50</> to repair HULL"); it read like any
    -- other cost (Repair Station, VM, 2026-10-14).
    if not needs then
        local short = wording:gsub("%[[^%[%]]*%]", ""):match("<ColorNegative>([^<]-)</>")
        local res = short and plain(short):gsub("%s*[%d,]+$", "")
        if res and res ~= "" then parts[#parts + 1] = "Not enough " .. res end
    end
    crumb.at("events: rewards")
    local r = rewards(b)
    if r ~= "" then parts[#parts + 1] = r:sub(1, 1):upper() .. r:sub(2) end
    crumb.at("events: option_for")
    local o = option_for(b, wording)
    if o then
        crumb.at("events: risk")
        local ok, risk = pcall(function() return o.Risk end)
        local ok2, leaving = pcall(function() return o.bLeaving end)
        if ok and RISKS[risk] and not (ok2 and leaving) then parts[#parts + 1] = RISKS[risk] end
    end
    crumb.at("events: chances")
    local c = o and chances(o, b)
    if c then parts[#parts + 1] = c:sub(1, 1):upper() .. c:sub(2) end
    crumb.at("events: room_names")
    local better = o and room_names(o) or {}
    if #better > 0 then parts[#parts + 1] = "Better with " .. table.concat(better, " or ") end
    -- Position among the event's options, so one option is not heard as
    -- running into the next ("Leave the storage alone..." is not "Leave for
    -- now"; Casey, 2026-10-11).
    -- Heroes: the skill the option tests, and the way to choose one.
    -- Not on a locked option: "Locked: ... Left and Right choose a hero"
    -- offered a choice that cannot be made (Demon Planet, VM, 2026-10-15).
    local heroes = is_locked(b) and {} or heroes_of(b)
    if #heroes > 1 then
        local skill = o and attribute_of(o)
        local i = chosen[path_of(b)] or 1
        local h = (i > 1 and heroes[i]) and ("Hero: " .. heroes[i].name) or "Left and Right choose a hero"
        parts[#parts + 1] = (skill and (skill .. " task. ") or "") .. h
    end
    crumb.at("events: position")
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
        if p and p:find("^/Engine/Transient%.") and screen.shown(w) and is_locked(w) then
            out[#out + 1] = M.option_label(w)
        end
    end
    return table.concat(out, " ")
end

return M
