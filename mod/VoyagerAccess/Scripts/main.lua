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

local speech = require("speech")
local focus = require("focus")

speech.reset()
speech.say("Voyager Access loaded", true)
focus.install()
require("dialogue").install()
require("story").install()
require("popups").install()
require("quest").install()
require("help").install()
require("resources").install()
require("view").install()
require("awaymission").install()
require("whatsnew").install()
require("hotkeys").install()
require("credits").install()
require("techtree").install()
require("combat").install()
require("ship").install()
require("language").install()
require("keys").install()
require("reload")()
require("devcmd")()
