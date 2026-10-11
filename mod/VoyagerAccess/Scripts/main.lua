-- Voyager Access entry point. Speaks a startup line, speaks the focused
-- button whenever focus moves (focus.lua), and reads dialogue (dialogue.lua).
-- The triage-era 30-second dump of every text widget was removed
-- 2026-10-10: it scanned every widget and was no longer needed.

local speech = require("speech")
local focus = require("focus")

speech.reset()
speech.say("Voyager Access loaded", true)
focus.install()
require("dialogue").install()
require("popups").install()
require("quest").install()
require("help").install()
require("resources").install()
require("view").install()
require("keys").install()
require("devcmd")()
