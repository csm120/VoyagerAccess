"""system.lua: a point whose events are over does not repeat its scan text.

After the Spatial Anomaly event, the System Map said "Debris Field,
Spatial Anomaly, Our sensors have detected a small but stable spatial
anomaly. It is not dangerous, but could provide valuable scientific data,
done" (Casey's play, 2026-10-29): the text the scan found was kept and
said before "done", though the game's own panel no longer showed it.
Runs the real system.lua under lupa; status() is reached through
M.where's upvalues with the game stubbed.
"""
import pathlib
import unittest

try:
    import lupa
except ImportError:  # pragma: no cover
    lupa = None

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent / "mod" / "VoyagerAccess" / "Scripts"

STUBS = r"""
package.preload["speech"] = function() return { say = function() end } end
package.preload["crumb"] = function() return { at = function() end } end
package.preload["tr"] = function() return { word = function(w) return w end, fill = function(t) return t end } end
setmetatable(_G, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() end end
end })
STATE = 5
function FindFirstOf(c)
    if c == "STVEventSubsystem" then
        local es = {}
        function es:IsValid() return true end
        function es:GetEventStateById() return STATE end
        return es
    end
    return nil
end
function FindAllOf() return {} end
local function upvalue(fn, name)
    for i = 1, 200 do
        local n, v = debug.getupvalue(fn, i)
        if n == nil then return nil end
        if n == name then return v, i end
    end
end
function status_of(M, found_text, state)
    STATE = state
    local status = upvalue(M.where, "status")
    -- Scanned, nothing left in the point's resources, the scan's text kept.
    for i = 1, 200 do
        local n = debug.getupvalue(status, i)
        if n == nil then break end
        if n == "explored" then debug.setupvalue(status, i, function() return true end) end
        if n == "resources" then debug.setupvalue(status, i, function() return "" end) end
        if n == "found" then debug.setupvalue(status, i, { ["/Game/P1"] = found_text }) end
    end
    local poi = { EventIds = { ForEach = function(_, fn) fn(1, { get = function() return "E1" end }) end } }
    return status({ actor = {}, poi = poi, path = "/Game/P1" })
end
"""

FOUND = ("Spatial Anomaly, Our sensors have detected a small but stable spatial anomaly. "
         "It is not dangerous, but could provide valuable scientific data")


@unittest.skipIf(lupa is None, "lupa not installed")
class DonePointTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f"package.path = {str(SCRIPTS / '?.lua')!r} .. ';' .. package.path")
        self.lua.execute(STUBS)
        self.M = self.lua.execute("return (require('system'))")

    def status(self, state):
        return self.lua.globals().status_of(self.M, FOUND, state)

    def test_done_point_says_only_done(self):
        self.assertEqual(self.status(5), "done")

    def test_failed_point_says_only_done(self):
        self.assertEqual(self.status(7), "done")

    def test_point_with_an_event_left_keeps_the_scan_text(self):
        # The negative twin: the found text still matters while the event waits.
        self.assertEqual(self.status(2), FOUND)


if __name__ == "__main__":
    unittest.main()
