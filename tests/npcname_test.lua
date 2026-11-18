-- Looking up an NPC name for the card text must never touch GameTooltip:
-- the player may be reading an item tooltip, and hiding it every 1.5 s made
-- tooltips vanish while the card showed an NPC the game had not cached.
local ROOT = ...
local f = assert(io.open(ROOT .. "/functions.lua", "r"))
local src = f:read("*a")
f:close()
local chunk = src:match("(%-%- A private tooltip.-)function addon%.ReplaceNpcIds")
assert(chunk, "GetScanTooltip/GetNpcName not found in functions.lua")

local failures = 0
local function check(ok, msg)
    if not ok then failures = failures + 1; print("FAIL: " .. msg) end
end

GameTooltip = setmetatable({}, {__index = function(_, k)
    return function() check(false, "GameTooltip:" .. k .. " was called") end
end})
WorldFrame = {}
local now = 100
GetTime = function() return now end

local cache = {[448] = "Hogger"}
local lines = {}
local created = 0
CreateFrame = function(kind, name)
    created = created + 1
    local tip = {}
    function tip:GetName() return name end
    function tip:SetOwner() end
    function tip:ClearLines() lines = {} end
    function tip:SetHyperlink(link)
        local id = tonumber(link:match("(%d+)$"))
        if cache[id] then lines = {cache[id]} end
    end
    function tip:NumLines() return #lines end
    function tip:Hide() end
    _G[name .. "TextLeft1"] = {GetText = function() return lines[1] end}
    return tip
end

local addon = {IsSecretValue = function() return false end}
assert(loadstring("local addon = ...\n" .. chunk))(addon)

check(addon.GetNpcName(448) == "Hogger", "cached NPC name read from scan tooltip")
check(addon.GetNpcName(99999) == nil, "uncached NPC gives nil")
now = now + 2
check(addon.GetNpcName(99999) == nil, "uncached NPC retried without GameTooltip")
check(created == 1, "one scan tooltip reused")

print(failures == 0 and "ok" or (failures .. " failures"))
return failures
