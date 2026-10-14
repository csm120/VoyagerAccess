-- Story overlays (WBP_SequentialStoryOverlay_C): narration typed out a line
-- at a time over a scene, with no dialogue window and no cutscene input. A
-- new full-game campaign opens with one ("So, a few days back, this Captain
-- Janeway breezes into my cozy penal colony..."), and it was silent while
-- the mod announced the System Map behind it (2026-10-14, VM).
--
-- Each line is spoken whole from the typewriter's TargetText, as
-- dialogue.lua does, and queued so a line does not cut off the one before.
local speech = require("speech")
local screen = require("screen")

local M = {}

local INTERVAL_MS = 150
local last_line = nil

local function path_of(obj)
    return obj:GetFullName():match("^%S+%s+(.+)$")
end

-- The overlay on screen now, or nil.
local function overlay()
    for _, w in ipairs(FindAllOf("WBP_SequentialStoryOverlay_C") or {}) do
        if w:IsValid() then
            local p = path_of(w)
            if p and p:find("^/Engine/Transient%.") and screen.shown(w) then return w, p end
        end
    end
    return nil
end

function M.active()
    local ok, w = pcall(overlay)
    return ok and w ~= nil
end

local function clean(s)
    s = s:gsub("<[^>]*/>", ""):gsub("<[^>]*>", "")
    return (s:gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

local function poll()
    local w, p = overlay()
    if not w then
        last_line = nil
        return
    end
    local prefix = p .. "."
    for _, t in ipairs(FindAllOf("WBP_TypeWriterRichTextBlock_C") or {}) do
        if t:IsValid() then
            local tp = path_of(t)
            if tp and tp:sub(1, #prefix) == prefix and screen.shown(t) then
                local ok, s = pcall(function() return t.TargetText:ToString() end)
                s = ok and type(s) == "string" and clean(s) or ""
                if s ~= "" and s ~= last_line then
                    last_line = s
                    print("[VoyagerAccess] story: " .. s .. "\n")
                    speech.say(s, false)
                    require("dialogue").remember(s)
                end
            end
        end
    end
end

function M.install()
    LoopInGameThreadWithDelay(INTERVAL_MS, function()
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] story error: " .. tostring(err) .. "\n") end
    end)
end

return M
