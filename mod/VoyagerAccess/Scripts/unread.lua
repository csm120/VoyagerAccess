-- Development only: logs each window shown on screen whose class no module
-- of the mod names, with its first texts, once per class. Run alongside the
-- VM explore scripts so silent screens in later sectors turn up in the log
-- instead of by ear (technique review, 2026-10-16). Needs the dev flag and
-- its own flag file %LOCALAPPDATA%\VoyagerAccess\unread; the installer
-- creates neither.
local M = {}

local FLAG = (os.getenv("LOCALAPPDATA") or ".") .. "\\VoyagerAccess\\unread"
local known = nil
local logged = {}

-- Every WBP_ class name written anywhere in the mod's own scripts.
local function load_known()
    known = {}
    local src = debug.getinfo(1, "S").source
    local dir = src:match("^@(.*[/\\])") or ""
    for name in pairs(package.loaded) do
        if type(name) == "string" and name:match("^[%w_]+$") then
            local f = io.open(dir .. name .. ".lua", "r")
            if f then
                local s = f:read("*a")
                f:close()
                for w in s:gmatch("(WBP_[%w_]+)") do
                    known[(w:gsub("_C$", ""))] = true
                end
            end
        end
    end
end

-- The first few texts under a widget, for the log line.
local function texts_of(w)
    local out = {}
    local prefix = w:GetFullName():match("^%S+%s+(.+)$") .. "."
    for _, cls in ipairs({ "TextBlock", "RichTextBlock" }) do
        for _, t in ipairs(FindAllOf(cls) or {}) do
            if #out >= 4 then break end
            local tp = t:IsValid() and t:GetFullName():match("^%S+%s+(.+)$")
            if tp and tp:sub(1, #prefix) == prefix and require("screen").shown(t) then
                local ok, s = pcall(function() return t:GetText():ToString() end)
                if ok and s and s:match("%S") then out[#out + 1] = s:gsub("%s+", " "):sub(1, 60) end
            end
        end
    end
    return table.concat(out, " | ")
end

local function poll()
    if not known then load_known() end
    local lib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local uw = StaticFindObject("/Script/UMG.UserWidget")
    local pc = FindFirstOf("PlayerController")
    if not (lib and uw and pc and pc:IsValid()) then return end
    local found = {}
    lib:GetAllWidgetsOfClass(pc, found, uw, true)
    for _, p in pairs(found) do
        local w = p:get()
        if w and w:IsValid() then
            local cls = w:GetClass():GetFName():ToString():gsub("_C$", "")
            if cls:find("^WBP_") and not known[cls] and not logged[cls] and require("screen").shown(w) then
                logged[cls] = true
                local okt, t = pcall(texts_of, w)
                print("[VoyagerAccess] unread: " .. cls .. " | " .. (okt and t or "?") .. "\n")
            end
        end
    end
end

function M.install()
    local f = io.open(FLAG, "r")
    if not f then return end
    f:close()
    print("[VoyagerAccess] unread window log on\n")
    LoopInGameThreadWithDelay(2000, function()
        local ok, err = pcall(poll)
        if not ok then print("[VoyagerAccess] unread error: " .. tostring(err) .. "\n") end
    end)
end

return M
