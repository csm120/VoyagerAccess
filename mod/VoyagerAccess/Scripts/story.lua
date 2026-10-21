-- Story overlays (WBP_SequentialStoryOverlay_C): narration typed out a line
-- at a time over a scene, with no dialogue window and no cutscene input. A
-- new full-game campaign opens with one ("So, a few days back, this Captain
-- Janeway breezes into my cozy penal colony..."), and it was silent while
-- the mod announced the System Map behind it (2026-10-14, VM).
--
-- Each line is taken whole as the overlay's typewriter is given it, for R
-- to repeat; the lines are voiced, so not spoken.
--
-- From the typewriter's own PlayLine(InLine, ...) (STVTypewriterRichTextBlock,
-- native, hooked once), not from a 150 ms scan of every typewriter widget:
-- the mod's loops held the game long enough to swallow keys (firefly82,
-- 2026-10-21). OPEN POINT: the window census of 2026-10-21 saw PlayLine
-- called for away mission texts but met no story overlay; a call from C++
-- would not reach the hook, so this is to be checked with a new campaign's
-- opening.
local M = {}

local HOOK = "/Script/STVoyager.STVTypewriterRichTextBlock:PlayLine"
local last_line = nil
local hooked = false
local overlay_path = nil   -- the overlay whose typewriter last played a line

-- True while that overlay is on screen (help.lua, quest.lua).
function M.active()
    if not overlay_path then return false end
    local ok, shown = pcall(function()
        local w = StaticFindObject(overlay_path)
        return w ~= nil and w:IsValid() and require("screen").shown(w)
    end)
    return ok and shown == true
end

local function clean(s)
    s = require("text").prep(s)  -- icons beside numbers (text.lua)
    s = s:gsub("<[^>]*/>", ""):gsub("<[^>]*>", "")
    return (s:gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

function M.install()
    if hooked then return end
    hooked = pcall(RegisterHook, HOOK, function(ctx, line)
        local okp, p = pcall(function() return ctx:get():GetFullName() end)
        if not okp or not p then return end
        -- A challenge result's story being typed (away missions): the
        -- mission reader looks at its window (awaymission.lua).
        if p:find("WBP_AwayMission_ChallengeResult", 1, true) then
            ExecuteInGameThread(function() pcall(function() require("awaymission").request_poll() end) end)
            return
        end
        if not p:find("WBP_SequentialStoryOverlay_C", 1, true) then return end
        overlay_path = p:match("^%S+%s+(.-WBP_SequentialStoryOverlay_C_%d+)")
        local okl, s = pcall(function() return line:get():ToString() end)
        s = okl and type(s) == "string" and clean(s) or ""
        if s ~= "" and s ~= last_line then
            last_line = s
            print("[VoyagerAccess] story: " .. s .. "\n")
            -- Not spoken: the overlay's lines are voiced (Q's opening,
            -- Casey, 2026-10-14: "we hear the dialog so we don't need
            -- the audio to be spoken via NVDA"). R still repeats one.
            require("dialogue").remember(s)
        end
    end)
    print("[VoyagerAccess] story: line hook " .. (hooked and "installed" or "not installed") .. "\n")
end

return M
