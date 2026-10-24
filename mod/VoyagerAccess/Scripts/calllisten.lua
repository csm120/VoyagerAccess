-- Listener only, for finding the game's event behind an incoming call
-- (2026-10-24). view.lua learns of a call from the navigation bar's
-- UpdateIncomingCallButton, which the game calls about 19 times a second
-- whether anything changed or not (probe e1: 5,759 calls in 300 s), so that
-- hook is a poll at the game's rate. The calls themselves are the journey
-- subsystem's CurrentIncomingCalls (header dump). Which function adds one
-- is not known, and a call cannot be brought on at will, so this waits for
-- one in normal play: each journey function below that the game runs
-- through its reflection is logged, and on the next tick the call count is
-- read once (GetIncomingCallsNum); a change is logged with the function
-- that came before it. Says nothing, changes nothing.
local M = {}

local FNS = { "DeclareEventOrTrigger", "TryStartEventById", "RunCurrentEvents", "BeginScheduledReport",
    "OnResolvedEvent", "OnTravelCompleted", "OnTravelConfirmed", "PassCycles", "OnStateTransitionFinished",
    "OnDismissedScheduledReport", "ClickedIncomingCall", "UpdateTravelPause", "OnPlayerDeclaredWait" }

local last_count = nil
local recent = {}   -- the last journey functions seen, newest last

local function count_now()
    local n = nil
    pcall(function()
        local j = FindFirstOf("STVJourneySubsystem")
        if j and j:IsValid() then n = j:GetIncomingCallsNum() end
    end)
    return n
end

local function after(fname)
    recent[#recent + 1] = string.format("%.3f %s", os.clock(), fname)
    if #recent > 8 then table.remove(recent, 1) end
    -- A pre hook: the function has run by the next tick.
    ExecuteInGameThread(function()
        local n = count_now()
        if n == nil or n == last_count then return end
        print(string.format("[VoyagerAccess] calls: %s to %s after %s (before it: %s)\n",
            tostring(last_count), tostring(n), fname, table.concat(recent, ", ")))
        last_count = n
    end)
end

function M.install()
    local got = {}
    for _, f in ipairs(FNS) do
        local path = "/Script/STVoyager.STVJourneySubsystem:" .. f
        if StaticFindObject(path) and pcall(RegisterHook, path, function() after(f) end) then got[#got + 1] = f end
    end
    last_count = count_now()
    print("[VoyagerAccess] calls: listening on " .. #got .. " of " .. #FNS .. " journey functions, calls now " .. tostring(last_count) .. "\n")
end

-- view.lua tells when the bar's button shows a waiting call, so the log
-- has both sides next to each other.
function M.button_seen()
    if last_count == nil and #recent == 0 then return end   -- not installed
    print("[VoyagerAccess] calls: button shows a call; count " .. tostring(count_now()) .. ", journey functions before: " .. table.concat(recent, ", ") .. "\n")
end

return M
