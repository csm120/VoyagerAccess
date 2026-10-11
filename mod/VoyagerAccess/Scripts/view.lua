-- V switches between the ship view and the System Map. The game has no
-- keyboard binding for it, only the Ship and System buttons in the HUD's
-- navigation bar (ShowShipButton, ShowSystemButton, found 2026-10-11);
-- until then only tutorials switched views for Casey. V is unbound.

local speech = require("speech")
local screen = require("screen")

local M = {}

local function find(name)
    for _, b in ipairs(FindAllOf("CommonButtonBase") or {}) do
        local p = b:IsValid() and b:GetFullName():match("^%S+%s+(.+)$")
        if p and p:find("WBP_NavigationBar", 1, true) and p:find("%." .. name .. "$") and screen.shown(b) then
            return b
        end
    end
    return nil
end

function M.toggle()
    local to_map = require("ship").active()
    local b = find(to_map and "ShowSystemButton" or "ShowShipButton")
    if not b then
        speech.say("Cannot switch view here", true)
        return
    end
    b:HandleButtonPressed()
    b:HandleButtonReleased()
    b:HandleButtonClicked()
    speech.say(to_map and "System map" or "Ship view", true)
end

function M.install()
    require("keys").on("v", M.toggle)
end

return M
