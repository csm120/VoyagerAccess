-- The mod's own words in the game's language (firefly82's review,
-- 2026-10-20: "Deck", "Tier", "on", "Damaged" stayed English in the German
-- game; Casey: every language the game supports). The game ships German,
-- Spanish, French, Japanese, Polish, Russian and Simplified Chinese
-- (its Localization folders); each has a table in tr_<code>.lua.
--
-- A table maps the mod's English, written as a template, to the language:
--   ["Ship view"] = "Schiffsansicht",
--   ["{n} of {n}"] = "{n} von {n}",
-- {n} stands for a number and {s} for any text between fixed words; the
-- translation uses them in the same order, or names them {1}, {2} to
-- reorder ("{s} needs {n}" -> "{2} braucht {1}" is allowed).
--
-- Two ways in:
--   M.apply(text) runs in speech.say on every line outside English, so the
--   phrases are translated wherever they are built. Only templates with
--   two or more words, or a fixed word next to {n}, are used here: a lone
--   English word such as "on" is a real word in French game text.
--   M.word(english) is the exact lookup for those lone words, called where
--   the mod makes them (a room's state, a list's "selected").

local M = {}

local CODES = { de = true, es = true, fr = true, ja = true, pl = true, ru = true, ["zh-Hans"] = true }

local function culture()
    local ok, c = pcall(function()
        return StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary"):GetCurrentCulture():ToString()
    end)
    if not (ok and type(c) == "string") then return nil end
    if CODES[c] then return c end
    if c:match("^zh") then return "zh-Hans" end
    local base = c:match("^(%a+)")
    return (base and CODES[base]) and base or nil
end

local loaded = {}      -- code -> { words = {}, compiled = { {pat, rep} } }
local code_now, checked_at = nil, false

local function esc(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

-- One template to a Lua pattern and its replacement. The ends are tied to
-- word boundaries so "Deck {n}" does not match inside "Decks".
local function compile(key, value)
    local pat, n, kinds = "", 0, {}
    local i = 1
    while i <= #key do
        local a, b, kind = key:find("{([ns])}", i)
        if not a then pat = pat .. esc(key:sub(i)); break end
        pat = pat .. esc(key:sub(i, a - 1))
        n = n + 1
        kinds[n] = kind
        -- {s} stays inside its sentence: at the end of a template it takes
        -- the rest of the sentence (lazy would take nothing, and a
        -- translation that moves it would lose it), elsewhere as little as
        -- reaches the next fixed word.
        local last = b == #key
        pat = pat .. (kind == "n" and "([%+%-]?%d[%d,%.]*)" or (last and "([^%.]*)" or "([^%.]-)"))
        i = b + 1
    end
    if key:match("^%w") then pat = "%f[%w]" .. pat end
    if key:match("%w$") then pat = pat .. "%f[%W]" end
    -- {n} and {s} take the template's slots in order; {1}, {2} name a slot
    -- when the language needs another word order.
    local rep, k = value:gsub("%%", "%%%%"), 0
    rep = rep:gsub("{(%d)}", "%%%1"):gsub("{[ns]}", function() k = k + 1; return "%" .. k end)
    -- Ranked by fixed letters, not length: "{s}, {s}, {s}{n} of {n}" is
    -- long but says almost nothing, and taking a line first it kept
    -- ", opens {n}: {s}" from ever matching (German table, 2026-10-20).
    local fixed = key:gsub("{[ns]}", ""):gsub("[^%a]", "")
    -- A number ending the template takes a comma or full stop after it
    -- ("26,"), and the next phrase lost its comma: ", base attack power 26"
    -- stayed English (German Combat tab, VM, 2026-10-20). pass() gives the
    -- separator back.
    local n_last = kinds[n] == "n" and key:sub(-3) == "{n}"
    return { pat = pat, rep = rep, len = #fixed, slots = n, kinds = kinds, n_last = n_last }
end

-- Safe for the line-wide pass: two or more words, a word beside {n}, or
-- one English word of five letters or more ("selected", "Damaged"), which
-- the other languages' game texts do not use. Short words ("on", "off",
-- "Tier") only through M.word: French game text has its own "on".
-- Some long English words are in the game's own German texts all the same,
-- and the pass changed them: "die Operation" became "die Betrieb", the tech
-- tree's "Level 2" became "Stufe 2" (firefly82, 2026-10-24, checked against
-- the game's German string tables: Operation in 10 texts, Level in room and
-- tech names, Story and Research in one each). Those go through M.word only.
local GAME_WORDS = { Operation = true, Level = true, Story = true, Research = true }
local function line_safe(key)
    if GAME_WORDS[key] then return false end
    local plain = key:gsub("{[ns]}", "")
    local words = select(2, plain:gsub("%a+", ""))
    if words >= 2 or (words == 1 and key:find("{n}", 1, true) ~= nil) then return true end
    -- An English word against a colon ("Goal: {s}", "{s}: none") does not
    -- occur in the other languages' game text either.
    if words == 1 and (key:find("%a:") or key:find(":%s*%a")) then return true end
    local word = plain:match("%a+")
    -- One word with a {s} slot ("Needs {s}", "victory, {s}") follows the
    -- same five-letter rule.
    return words == 1 and word ~= nil and #word >= 5
end

local function load(code)
    if loaded[code] ~= nil then return loaded[code] end
    local ok, t = pcall(require, "tr_" .. code:gsub("%-", "_"))
    if not (ok and type(t) == "table") then
        print("[VoyagerAccess] tr: no table for " .. code .. ": " .. tostring(t) .. "\n")
        loaded[code] = false
        return false
    end
    local data = { words = t, compiled = {} }
    for key, value in pairs(t) do
        if type(key) == "string" and type(value) == "string" and value ~= "" and line_safe(key) then
            data.compiled[#data.compiled + 1] = compile(key, value)
            -- A lowercase template also starts a sentence: events.lua
            -- capitalizes each part ("Up to 49 Tritanium" stayed English,
            -- VM, 2026-10-20). The translation's first letter follows when
            -- it is a plain letter (other scripts keep their own case).
            local cap = key:gsub("^%l", string.upper)
            if cap ~= key and t[cap] == nil then
                data.compiled[#data.compiled + 1] = compile(cap, (value:gsub("^%l", string.upper)))
            end
        end
    end
    -- Longest first, so "Decks {n} to {n}" wins over "{n} to {n}".
    table.sort(data.compiled, function(a, b)
        if a.len ~= b.len then return a.len > b.len end
        return a.slots < b.slots
    end)
    loaded[code] = data
    print("[VoyagerAccess] tr: " .. code .. ", " .. #data.compiled .. " phrases\n")
    return data
end

-- The current language's table, or nil in English. The language is read
-- once, and again when language.lua, which reads it after every input,
-- says it changed (M.culture_changed). It was read again once a second,
-- so for up to a second after a change the mod spoke the old language:
-- "Spielsprache auf English geändert" (2026-10-25).
local function current()
    if not checked_at then
        code_now = culture()
        checked_at = true
    end
    if not code_now then return nil end
    local d = load(code_now)
    return d or nil
end

-- A translated piece is parked behind a marker (control characters, no
-- letters or digits) until the pass ends, so no later template translates
-- it again: "Enter: select" became "Enter, выбор" and then matched the
-- "Enter: {s}" template a second time (Russian table, 2026-10-20).
local function expand(rep, caps)
    return (rep:gsub("%%([%d%%])", function(c)
        if c == "%" then return "%" end
        return caps[tonumber(c)] or ""
    end))
end

-- One pass of every template over text. Text taken by a {s} slot gets its
-- own pass first ("Press Enter: Ship view" left "Ship view" English inside
-- the slot), two levels deep at most.
local function pass(text, d, store, depth)
    for _, c in ipairs(d.compiled) do
        local ok, out = pcall(string.gsub, text, c.pat, function(...)
            local caps = { ... }
            local back = ""
            if c.n_last and type(caps[c.slots]) == "string" then
                local num, sep = caps[c.slots]:match("^(.-)([,%.]+)$")
                if num then caps[c.slots], back = num, sep end
            end
            if depth < 3 then
                for i, kind in ipairs(c.kinds) do
                    if kind == "s" and type(caps[i]) == "string" and caps[i]:find("%a") then
                        caps[i] = pass(caps[i], d, store, depth + 1)
                    end
                end
            end
            store[#store + 1] = expand(c.rep, caps)
            return "\1" .. ("\2"):rep(#store) .. "\1" .. back
        end)
        if ok then text = out end
    end
    return text
end

-- Lines already translated, per language table: spoken lines repeat a lot
-- (room names, list positions, "Ship view"), and each new one runs about 850
-- patterns (outside review of firefly82's patch, 2026-10-21). Cleared when
-- it grows past MEMO_MAX lines or the language changes.
local MEMO_MAX = 400
local memo, memo_for, memo_n = {}, nil, 0

function M.apply(text)
    if type(text) ~= "string" or text == "" then return text end
    local d = current()
    if not d then return text end
    if memo_for ~= d or memo_n >= MEMO_MAX then memo, memo_for, memo_n = {}, d, 0 end
    local hit = memo[text]
    if hit then return hit end
    local original = text
    local store = {}
    text = pass(text, d, store, 1)
    -- Markers can sit inside a later piece's slot; unwrap until none left.
    for _ = 1, 10 do
        local n
        text, n = text:gsub("\1(\2+)\1", function(s) return store[#s] or "" end)
        if n == 0 then break end
    end
    memo[original] = text
    memo_n = memo_n + 1
    return text
end

function M.word(english)
    local d = current()
    if not d then return english end
    local w = d.words[english]
    return (type(w) == "string" and w ~= "") and w or english
end

-- The game's own text in lower case, but only in English: the mod's
-- sentences put game words mid-line ("Warp core tier 2"), and lowering
-- them in German broke nouns ("Warpkern stufe 2", firefly82's review,
-- 2026-10-20). Other languages keep the game's casing.
function M.lower(s)
    if type(s) ~= "string" or current() then return s end
    return s:lower()
end

-- The exact lookup for a short template the line pass leaves alone
-- ("{s} tab"), with its slots filled in order: M.fill("{s} tab", "Crew").
-- English, or a template the table lacks, fills the English one.
function M.fill(template, ...)
    local args = { ... }
    local d = current()
    local w = d and d.words[template]
    local out = (type(w) == "string" and w ~= "") and w or template
    local k = 0
    out = out:gsub("{(%d)}", function(i) return "\0" .. i .. "\0" end)
    out = out:gsub("{[ns]}", function() k = k + 1; return "\0" .. k .. "\0" end)
    return (out:gsub("%z(%d)%z", function(i) return tostring(args[tonumber(i)] or "") end))
end

-- language.lua: the game's language has changed; read it again on the
-- next lookup.
function M.culture_changed()
    checked_at = false
end

-- Development: the language in use and how many phrases it has.
function M.status()
    local d = current()
    return (code_now or "en") .. (d and (", " .. #d.compiled .. " phrases") or "")
end

return M
