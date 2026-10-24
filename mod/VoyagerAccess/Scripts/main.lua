-- Voyager Access entry point. Speaks a startup line, speaks the focused
-- button whenever focus moves (focus.lua), and reads dialogue (dialogue.lua).
-- The triage-era 30-second dump of every text widget was removed
-- 2026-10-10: it scanned every widget and was no longer needed.

-- Development only (the "unread" flag file, as unread.lua): every poll loop
-- leaves a crash breadcrumb naming its module. That is how a crash was
-- traced to help.lua's front_window (VM, 2026-10-16). Wrapped once: a
-- reload runs this file again.
if not VOYAGER_LOOP_WRAPPED then
    local flag = io.open((os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\unread", "r")
    if flag then
        flag:close()
        VOYAGER_LOOP_WRAPPED = true
        local loop = LoopInGameThreadWithDelay
        LoopInGameThreadWithDelay = function(ms, fn)
            local name = "?"
            pcall(function() name = (debug.getinfo(fn, "S").short_src or "?"):match("([%w_]+)%.lua") or "?" end)
            return loop(ms, function(...)
                require("crumb").at("loop: " .. name)
                return fn(...)
            end)
        end
    end
end

-- Development only: how long the mod's own work holds the game (timing.lua,
-- flag file "timing").
do
    local flag = io.open((os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\timing", "r")
    if flag then
        flag:close()
        require("timing").install()
    end
end

local speech = require("speech")
local focus = require("focus")

speech.reset()
speech.say("Voyager Access loaded", true)
focus.install()
require("dialogue").install()
require("story").install()
require("popups").install()
require("system").install()
require("quest").install()
require("help").install()
require("resources").install()
require("view").install()
-- Development only (flag file "calls"): which game function brings an
-- incoming call. It answered on 2026-10-24 (the count changes right after
-- OnStateTransitionFinished or OnTravelCompleted), and its 13 hooks are no
-- cost to put on every player (Fable review, 2026-10-24).
do
    local flag = io.open((os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\calls", "r")
    if flag then
        flag:close()
        pcall(function() require("calllisten").install() end)
    end
end
require("awaymission").install()
require("whatsnew").install()
require("hotkeys").install()
require("credits").install()
require("techtree").install()
require("combat").install()
require("ship").install()
require("events").install()
require("language").install()
require("keys").install()
require("reload")()
require("devcmd")()
